/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class FirmwareUpgradeManager : FirmwareUpgradeController, ConnectionStateObserver {
    
    private let TAG = "FirmwareUpgradeManager"
    
    private let imageManager: ImageManager
    private let defaultManager: DefaultManager
    private let delegate: FirmwareUpgradeDelegate
    
    public var mode: FirmwareUpgradeMode = .testAndConfirm
    private var imageData: Data!
    private var hash: Data!
    
    private var state: FirmwareUpgradeState
    private var paused: Bool = false
    
    //**************************************************************************
    // MARK: Initializer
    //**************************************************************************
    
    public init(transporter: McuMgrTransport, delegate: FirmwareUpgradeDelegate) {
        self.imageManager = ImageManager(transporter: transporter)
        self.defaultManager = DefaultManager(transporter: transporter)
        self.delegate = delegate
        self.state = .none
    }
    
    //**************************************************************************
    // MARK: Control Functions
    //**************************************************************************
    
    /// Start the firmware upgrade.
    public func start(data: Data) throws {
        objc_sync_enter(self)
        if state != .none {
            Log.w(TAG, msg: "Firmware upgrade is already in progress")
            return
        }
        imageData = data
        hash = try McuMgrImage(data: imageData).hash
        
        delegate.upgradeDidStart(controller: self)
        validate()
        objc_sync_exit(self)
    }
    
    public func cancel() {
        objc_sync_enter(self)
        if state.isInProgress() {
            cancelPrivate()        }
        objc_sync_exit(self)
    }
    
    public func pause() {
        objc_sync_enter(self)
        if state.isInProgress() && !paused {
            Log.v(TAG, msg: "Pausing upgrade...")
            paused = true
            if state == .upload {
                imageManager.pauseUpload()
            }
        }
        objc_sync_exit(self)
    }
    
    public func resume() {
        objc_sync_enter(self)
        if paused {
            paused = false
            currentState()
        }
        objc_sync_exit(self)
    }
    
    public func isPaused() -> Bool {
        return paused
    }
    
    public func isInProgress() -> Bool {
        return state.isInProgress() && !paused
    }
    
    /// Sets the MTU of the image upload. The MTU must be between 23 and 1024
    /// (inclusive). The upload MTU determines the number of bytes sent in each
    /// upload request. The MTU will default the the maximum available to the
    /// phone and may change automatically if the end device's MTU is lower.
    ///
    /// - parameter mtu: The mtu to use in image upload.
    ///
    /// - returns: true if the mtu was within range, false otherwise
    public func setUploadMtu(mtu: Int) -> Bool {
        return imageManager.setMtu(mtu)
    }
    
    //**************************************************************************
    // MARK: Firmware Upgrade State Machine
    //**************************************************************************
    
    private func setState(_ state: FirmwareUpgradeState) {
        objc_sync_enter(self)
        let previousState = self.state
        self.state = state
        if state != previousState {
            delegate.upgradeStateDidChange(from: previousState, to: state)
        }
        objc_sync_exit(self)
    }
    
    private func validate() {
        setState(.validate)
        if !paused {
            imageManager.list(callback: validateCallback)
        }
    }
    
    private func upload() {
        setState(.upload)
        if !paused {
            _ = imageManager.upload(data: [UInt8](imageData), delegate: self)
        }
    }
    
    private func test() {
        setState(.test)
        if !paused {
            imageManager.test(hash: [UInt8](hash), callback: testCallback)
        }
    }
    
    private func confirm() {
        setState(.confirm)
        if !paused {
            imageManager.confirm(hash: [UInt8](hash), callback: confirmCallback)
        }
    }
    
    private func verify() {
        setState(.confirm)
        if !paused {
            // This will confirm the image on slot 0
            imageManager.confirm(callback: confirmCallback)
        }
    }
    
    private func reset() {
        setState(.reset)
        if !paused {
            defaultManager.transporter.addObserver(self)
            defaultManager.reset(callback: resetCallback)
        }
    }
    
    private func success() {
        objc_sync_enter(self)
        state = .none
        paused = false
        delegate.upgradeDidComplete()
        objc_sync_exit(self)
    }
    
    private func fail(error: Error) {
        objc_sync_enter(self)
        Log.e(TAG, error: error)
        cancelPrivate()
        delegate.upgradeDidFail(inState: state, with: error)
        objc_sync_exit(self)
    }
    
    private func cancelPrivate() {
        objc_sync_enter(self)
        if state == .upload {
            imageManager.cancelUpload()
        }
        state = .none
        paused = false
        objc_sync_exit(self)
    }
    
    private func currentState() {
        objc_sync_enter(self)
        if !paused {
            switch state {
            case .validate:
                validate()
            case .upload:
                imageManager.continueUpload()
            case .test:
                test()
            case .reset:
                reset()
            case .confirm:
                confirm()
            default:
                break
            }
        }
        objc_sync_exit(self)
    }
    
    //**************************************************************************
    // MARK: McuMgrCallbacks
    //**************************************************************************
    
    /// Callback for the VALIDATE state.
    ///
    /// This callback will fail the upgrade on error and continue to the next
    /// state on success.
    private lazy var validateCallback: McuMgrCallback<McuMgrImageStateResponse> =
    { [unowned self] (response: McuMgrImageStateResponse?, error: Error?) in
        if let error = error {
            print(error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Validation response is nil!"))
            return
        }
        Log.v(self.TAG, msg: "Validation response: \(response)")
        // Check for McuMgrReturnCode error.
        if !response.isSuccess() {
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        // Check that the image array exists.
        guard let images = response.images, images.count > 0 else {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }
        // Check if the new firmware is different then the active one.
        if Data(bytes: images[0].hash) == self.hash {
            if images[0].confirmed {
                // The new firmware is already active and confirmed.
                // No need to do anything.
                self.success()
            } else {
                // The new firmware is in test mode.
                switch self.mode {
                case .confirmOnly, .testAndConfirm:
                    self.confirm()
                case .testOnly:
                    self.success()
                }
            }
            return
        }
        // Check if the firmware has already been uploaded.
        if images.count > 1 && Data(bytes: images[1].hash) == self.hash {
            // Firmware is identical to the one in slot 1. No need to send
            // anything.
            
            // If the test and confirm commands were not sent, proceed
            // with next state.
            if !images[1].pending {
                switch self.mode {
                case .testOnly, .testAndConfirm:
                    self.test()
                case .confirmOnly:
                    self.confirm()
                }
                return
            }
            
            // If the image was already confirmed, reset (if confirm was
            // intended), or fail.
            if images[1].permanent || images[1].confirmed {
                switch self.mode {
                case .confirmOnly, .testAndConfirm:
                    self.reset()
                case .testOnly:
                    self.fail(error: FirmwareUpgradeError.unknown("Image already confirmed. Can't be tested!"))
                }
                return
            }
            
            // If image was not confirmed, but test command was sent,
            // confirm or reset.
            switch self.mode {
            case .confirmOnly:
                self.confirm()
            case .testOnly, .testAndConfirm:
                self.reset()
            }
        }
        
        // Validation successful, begin with image upload.
        self.upload()
    }
    
    /// Callback for the TEST state.
    ///
    /// This callback will fail the upgrade on error and continue to the next
    /// state on success.
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
        // Check for McuMgrReturnCode error.
        if !response.isSuccess() {
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        // Check that the image array exists.
        guard let images = response.images else {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }
        // Check that we have 2 images in the array.
        if images.count != 2 {
            self.fail(error: FirmwareUpgradeError.unknown("Test response does not contain enough info."))
            return
        }
        // Check that the image in slot 1 is pending (i.e. test succeeded).
        if !images[1].pending {
            self.fail(error: FirmwareUpgradeError.unknown("Tested image is not in a pending state."))
            return
        }
        // Test image succeeded. Begin device reset.
        self.reset()
    }
    
    public func peripheral(_ transport: McuMgrTransport, didChangeStateTo state: CBPeripheralState) {
        transport.removeObserver(self)
        Log.i(self.TAG, msg: "Reset successful")
        switch mode {
        case .testAndConfirm:
            verify()
        default:
            success()
        }
    }
    
    /// Callback for the RESET state.
    ///
    /// This callback will fail the upgrade on error. On success, the reset
    /// poller will be started after a 3 second delay.
    private lazy var resetCallback: McuMgrCallback<McuMgrResponse> =
    { [unowned self] (response: McuMgrResponse?, error: Error?) in
        if let error = error {
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Reset response is nil!"))
            return
        }
        // Check for McuMgrReturnCode error.
        if !response.isSuccess() {
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        Log.i(self.TAG, msg: "Reset request sent. Waiting for reset...")
    }
    
    /// Callback for the CONFIRM state.
    ///
    /// This callback will fail the upload on error or move to the next state on
    /// success.
    private lazy var confirmCallback: McuMgrCallback<McuMgrImageStateResponse> =
    { [unowned self] (response: McuMgrImageStateResponse?, error: Error?) in
        if let error = error {
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Confirm response is nil!"))
            return
        }
        Log.v(self.TAG, msg: "Confirm response: \(response)")
        // Check for McuMgrReturnCode error.
        if !response.isSuccess() {
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        // Check that the image array exists.
        guard let images = response.images else {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }
        // Check that we have at least one image in the array.
        if images.count == 0 {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }
        
        switch self.mode {
        case .confirmOnly:
            // The new image should be in slot 1.
            if images.count != 2 {
                self.fail(error: FirmwareUpgradeError.invalidResponse(response))
                return
            }
            // Check that the new image is in permanent state.
            if !images[1].permanent {
                self.fail(error: FirmwareUpgradeError.unknown("Image is not in a permanent state."))
                return
            }
            // Image was confirmed, reset the device.
            self.reset()
        case .testAndConfirm:
            // Check that the upgrade image has successfully booted.
            if Data(bytes: images[0].hash) != self.hash {
                self.fail(error: FirmwareUpgradeError.unknown("Device failed to boot into new image."))
                return
            }
            // Check that the new image is in confirmed state.
            if !images[0].confirmed {
                self.fail(error: FirmwareUpgradeError.unknown("Image is not in a confirmed state."))
                return
            }
            // Confirm successful.
            self.success()
        case .testOnly:
            // Impossible state. Ignore.
            break
        }
    }
}

//******************************************************************************
// MARK: ImageUploadDelegate
//******************************************************************************

extension FirmwareUpgradeManager: ImageUploadDelegate {
    
    public func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        delegate.uploadProgressDidChange(bytesSent: bytesSent, imageSize: imageSize, timestamp: timestamp)
    }
    
    public func uploadDidFail(with error: Error) {
        // If the upload fails, fail the upgrade.
        delegate.upgradeDidFail(inState: state, with: error)
    }
    
    public func uploadDidCancel() {
        delegate.upgradeDidCancel(state: state)
    }
    
    public func uploadDidFinish() {
        // On a successful upload move to the next state.
        switch mode {
        case .confirmOnly:
            confirm()
        case .testOnly, .testAndConfirm:
            test()
        }
    }
}

//******************************************************************************
// MARK: FirmwareUpgradeError
//******************************************************************************

public enum FirmwareUpgradeError: Error {
    case unknown(String)
    case invalidResponse(McuMgrResponse)
    case mcuMgrReturnCodeError(McuMgrReturnCode)
    case connectionFailedAfterReset
}

extension FirmwareUpgradeError: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .unknown(let message):
            return message
        case .invalidResponse(let response):
            return "Invalid response: \(response)"
        case .mcuMgrReturnCodeError(let code):
            return "Error: \(code)"
        case .connectionFailedAfterReset:
            return "Connection failed after reset"
        }
    }
}

//******************************************************************************
// MARK: FirmwareUpgradeState
//******************************************************************************

public enum FirmwareUpgradeState {
    case none, validate, upload, test, reset, confirm, success
    
    func isInProgress() -> Bool {
        return self == .validate || self == .upload || self == .test
            || self == .reset || self == .confirm
    }
}

//******************************************************************************
// MARK: FirmwareUpgradeMode
//******************************************************************************

public enum FirmwareUpgradeMode {
    case testOnly
    case confirmOnly
    case testAndConfirm
}

//******************************************************************************
// MARK: FirmwareUpgradeDelegate
//******************************************************************************

/// Callbacks for firmware upgrades started using FirmwareUpgradeManager.
public protocol FirmwareUpgradeDelegate {
    
    /// Called when the upgrade has started.
    ///
    /// - parameter controller: The controller that may be used to pause,
    ///   resume or cancel the upgrade.
    func upgradeDidStart(controller: FirmwareUpgradeController)
    
    /// Called when the firmware upgrade state has changed.
    ///
    /// - parameter previousState: The state before the change.
    /// - parameter newState: The new state.
    func upgradeStateDidChange(from previousState: FirmwareUpgradeState, to newState: FirmwareUpgradeState)
    
    /// Called when the firmware upgrade has succeeded.
    func upgradeDidComplete()
    
    /// Called when the firmware upgrade has failed.
    ///
    /// - parameter state: The state in which the upgrade has failed.
    /// - parameter error: The error.
    func upgradeDidFail(inState state: FirmwareUpgradeState, with error: Error)
    
    /// Called when the firmware upgrade has been cancelled using cancel()
    /// method. The upgrade may be cancelled only during uploading the image.
    /// When the image is uploaded, the test and/or confirm commands will be
    /// sent depending on the mode.
    func upgradeDidCancel(state: FirmwareUpgradeState)
    
    /// Called whnen the upload progress has changed.
    ///
    /// - parameter bytesSent: Number of bytes sent so far.
    /// - parameter imageSize: Total number of bytes to be sent.
    /// - parameter timestamp: The time that the successful response packet for
    ///   the progress was received.
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date)
}
