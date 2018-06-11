/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation


public class FirmwareUpgradeManager {
    
    private let TAG = "FirmwareUpgradeManager"
    
    private let transporter: McuMgrTransport
    private let imageManager: ImageManager
    private let defaultManager: DefaultManager
    private let delegate: FirmwareUpgradeDelegate
    private let imageData: Data
    private let hash: Data
    
    private var state: FirmwareUpgradeState
    private var paused: Bool = false
    
    private var resetPoller: DispatchQueue
    
    //*******************************************************************************************
    // MARK: Initializer
    //*******************************************************************************************
    
    public    init(transporter: McuMgrTransport, imageData: Data, delegate: FirmwareUpgradeDelegate) throws {
        self.transporter = transporter
        self.imageManager = ImageManager(transporter: transporter)
        self.defaultManager = DefaultManager(transporter: transporter)
        self.delegate = delegate
        self.imageData = imageData
        self.hash = try McuMgrImage(data: imageData).hash
        self.state = .none
        self.resetPoller = DispatchQueue(label: "FirmwareUpgradeResetPoller")
    }
    
    //*******************************************************************************************
    // MARK: Control Functions
    //*******************************************************************************************
    
    /// Start the firmware upgrade.
    public func start() {
        objc_sync_enter(self)
        if state != .none {
            Log.i(TAG, msg: "Firmware upgrade is already in progress")
            return
        }
        state = FirmwareUpgradeState.upload
        _ = imageManager.upload(data: [UInt8](imageData), delegate: self)
        delegate.didStart(manager: self)
        delegate.didStateChange(previousState: .none, newState: state)
        objc_sync_exit(self)
    }
    
    /// Cancel the firmware upgrade.
    public func cancel() {
        objc_sync_enter(self)
        if state.isInProgress() {
            _cancel()
            delegate.didCancel(state: state)
        }
        objc_sync_exit(self)
    }
    
    /// Pause the firmware upgrade.
    public func pause() {
        objc_sync_enter(self)
        Log.d(TAG, msg: "Pausing upgrade.")
        paused = true
        if state == .upload {
            imageManager.pauseUpload()
        }
        objc_sync_exit(self)
    }
    
    /// Resume a paused firmware upgrade.
    public func resume() {
        objc_sync_enter(self)
        if paused {
            paused = false
            // TODO currentState
        }
        objc_sync_exit(self)
    }
    
    private func _cancel() {
        objc_sync_enter(self)
        state = .none
        paused = false
        imageManager.cancelUpload()
        objc_sync_exit(self)
    }
    
    private func fail(error: Error) {
        objc_sync_enter(self)
        Log.e(TAG, error: error)
        _cancel()
        delegate.didFail(failedState: state, error: error)
        objc_sync_exit(self)
    }
    
    //*******************************************************************************************
    // MARK: Firmware Upgrade State Machine
    //*******************************************************************************************
    
    private func currentState() {
        objc_sync_enter(self)
        if paused {
            return
        }
        switch (state) {
        case .none:
            return
        case .upload:
            imageManager.continueUpload()
            break
        case .test:
            imageManager.test(hash: [UInt8](hash), callback: testCallback)
            break
        case .reset:
            defaultManager.reset(callback: resetCallback)
            break
        case .confirm:
            imageManager.confirm(hash: [UInt8](hash), callback: confirmCallback)
        case .success:
            break
        }
        objc_sync_exit(self)
    }
    
    private func nextState() {
        objc_sync_enter(self)
        if paused {
            return
        }
        let previousState = state
        switch (state) {
        case .none:
            return
        case .upload:
            state = .test
            Log.v(TAG, msg: "TEST STATE: Listing image state")
            imageManager.test(hash: [UInt8](hash), callback: testCallback)
            break
        case .test:
            state = .reset
            Log.v(TAG, msg: "RESET STATE: Listing image state")
            defaultManager.reset(callback: resetCallback)
            break
        case .reset:
            state = .confirm
            Log.v(TAG, msg: "CONFIRM STATE: Listing image state")
            imageManager.confirm(hash: [UInt8](hash), callback: confirmCallback)
            break
        case .confirm:
            state = .success
            Log.v(TAG, msg: "SUCCESS STATE: Listing image state")
        case .success:
            break
        }
        
        delegate.didStateChange(previousState: previousState, newState: state)
        
        if state == .success {
            delegate.didComplete()
        }
        objc_sync_exit(self)
    }
    
    //*******************************************************************************************
    // MARK: McuMgrCallbacks
    //*******************************************************************************************
    
    private lazy var imageListCallback: McuMgrCallback<McuMgrImageStateResponse> =
    { [unowned self] (response: McuMgrImageStateResponse?, error: Error?) in
        if let error = error {
            print(error)
            return
        }
        print(response!)
    }
    
    /// Callback for the TEST state.
    ///
    /// This callback will fail the upgrade on error and continue to the next state on success.
    private lazy var testCallback: McuMgrCallback<McuMgrImageStateResponse> =
    { [unowned self] (response: McuMgrImageStateResponse?, error: Error?) in
        if let error = error {
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Test response is nil!"))
            return
        }
        Log.v(self.TAG, msg: "Test response: \(response)")
        // Check for McuMgrReturnCode error
        if !response.isSuccess() {
            Log.e(self.TAG, msg: "Test failed due to McuManagerReturnCode error: \(response.returnCode)")
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        // Check that the image array exists
        guard let images = response.images else {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }
        // Check that we have 2 images in the array
        if images.count != 2 {
            Log.e(self.TAG, msg: "Test response does not contain enough info.")
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
        }
        // Check that the image in slot 1 is pending (i.e. test succeeded)
        if !images[1].pending {
            self.fail(error: FirmwareUpgradeError.unknown("Tested image is not in a pending state."))
        }
        // Test successful
        self.nextState()
    }
    
    /// Callback for the RESET state
    ///
    /// This callback will fail the upgrade on error. On success, the reset poller will be
    /// started after a 3 second delay
    private lazy var resetCallback: McuMgrCallback<McuMgrResponse> =
    { [unowned self] (response: McuMgrResponse?, error: Error?) in
        if let error = error {
            Log.e(self.TAG, error: error)
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Reset response is nil!"))
            return
        }
        Log.v(self.TAG, msg: "Reset response: \(response)")
        // Check for McuMgrReturnCode error
        if !response.isSuccess() {
            Log.e(self.TAG, msg: "Reset failed due to McuManagerReturnCode error: \(response.returnCode)")
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        
        // Start the reset poller dispatch work item after three seconds
        self.resetPoller.asyncAfter(deadline: DispatchTime.now() + .seconds(5), execute: {
            for i in 0..<5 {
                let lock = ResultLock(isOpen: false)
                self.imageManager.list(callback: { [unowned self] (response: McuMgrImageStateResponse?, error: Error?) in
                    if let error = error {
                        lock.open(error)
                        return
                    }
                    lock.open()
                })
                
                // Block on the waiting lock
                let result = lock.block()
                // If the result of the lock is success, move to the next state
                if case .success = result {
                    self.nextState()
                    return
                }
            }
            self.fail(error: FirmwareUpgradeError.connectionFailedAfterReset)
        })
    }
    
    /// Callback for the CONFIRM state
    ///
    /// This callback will fail the upload on error or move to the next state on success
    private lazy var confirmCallback: McuMgrCallback<McuMgrImageStateResponse> =
    { [unowned self] (response: McuMgrImageStateResponse?, error: Error?) in
        if let error = error {
            Log.e(self.TAG, error: error)
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Confirm response is nil!"))
            return
        }
        Log.v(self.TAG, msg: "Confirm response: \(response)")
        // Check for McuMgrReturnCode error
        if !response.isSuccess() {
            Log.e(self.TAG, msg: "Test failed due to McuManagerReturnCode error: \(response.returnCode)")
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        // Check that the image array exists
        guard let images = response.images else {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }
        // Check that we have 2 images in the array
        if images.count == 0 {
            Log.e(self.TAG, msg: "Test response does not contain enough info.")
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
        }
        // Check that the image in slot 1 is pending (i.e. test succeeded)
        if !images[0].confirmed {
            Log.e(self.TAG, msg: "Image is not in a confirmed state.")
            self.fail(error: FirmwareUpgradeError.unknown("Image is not in a confirmed state."))
        }
        // Test successful
        self.nextState()
    }
    
}

//*******************************************************************************************
// MARK: ImageUploadDelegate
//*******************************************************************************************

extension FirmwareUpgradeManager: ImageUploadDelegate {
    public func didProgressChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        delegate.didUploadProgressChange(bytesSent: bytesSent, imageSize: imageSize, timestamp: timestamp)
    }
    
    public func didFailUpload(bytesSent: Int, imageSize: Int, error: Error) {
        // If the upload fails, fail the upgrade
        delegate.didFail(failedState: state, error: error)
    }
    
    public func didFinishUpload() {
        // On a successful upload move to the next state
        nextState()
    }
}

//*******************************************************************************************
// MARK: FirmwareUpgradeError
//*******************************************************************************************

public enum FirmwareUpgradeError: Error {
    case unknown(String)
    case invalidResponse(McuMgrResponse)
    case mcuMgrReturnCodeError(McuMgrReturnCode)
    case connectionFailedAfterReset
}

//*******************************************************************************************
// MARK: FirmwareUpgradeState
//*******************************************************************************************

public enum FirmwareUpgradeState {
    case none, upload, test, reset, confirm, success
    
    func isInProgress() -> Bool {
        return self == .upload || self == .test || self == .reset || self == .confirm
    }
}

//*******************************************************************************************
// MARK: FirmwareUpgradeDelegate
//*******************************************************************************************

public protocol FirmwareUpgradeDelegate {
    func didStart(manager: FirmwareUpgradeManager)
    func didStateChange(previousState: FirmwareUpgradeState, newState: FirmwareUpgradeState)
    func didComplete()
    func didFail(failedState: FirmwareUpgradeState, error: Error)
    func didCancel(state: FirmwareUpgradeState)
    func didUploadProgressChange(bytesSent: Int, imageSize: Int, timestamp: Date)
}
