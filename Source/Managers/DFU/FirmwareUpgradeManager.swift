/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class FirmwareUpgradeManager : FirmwareUpgradeController, ConnectionObserver {
    
    private let TAG = "FirmwareUpgradeManager"
    
    private let imageManager: ImageManager
    private let defaultManager: DefaultManager
    private weak var delegate: FirmwareUpgradeDelegate?
    
    /// Cyclic reference is used to prevent from releasing the manager
    /// in the middle of an update. The reference cycle will be set
    /// when upgrade was started and released on success, error or cancel.
    private var cyclicReferenceHolder: (() -> FirmwareUpgradeManager)?
    
    private var imageData: Data!
    private var hash: Data!
    
    private var state: FirmwareUpgradeState
    private var paused: Bool = false
    
    /// Upgrade mode. The default mode is .testAndConfirm.
    public var mode: FirmwareUpgradeMode = .testAndConfirm
    
    /// Estimated time required for swapping images, in seconds.
    /// If the mode is set to `.testAndConfirm`, the manager will try to
    /// reconnect after this time. 0 by default.
    public var estimatedSwapTime: TimeInterval = 0.0
    private var resetResponseTime: Date?
    
    //**************************************************************************
    // MARK: Initializer
    //**************************************************************************
    
    public init(transporter: McuMgrTransport, delegate: FirmwareUpgradeDelegate?) {
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
            log(msg: "Firmware upgrade is already in progress", atLevel: .warn)
            return
        }
        imageData = data
        hash = try McuMgrImage(data: imageData).hash
        
        // Grab a strong reference to something holding a strong reference to self.
        cyclicReferenceHolder = { return self }
        
        delegate?.upgradeDidStart(controller: self)
        validate()
        objc_sync_exit(self)
    }
    
    public func cancel() {
        objc_sync_enter(self)
        if state == .upload {
            imageManager.cancelUpload()
            paused = false
        }
        objc_sync_exit(self)
    }
    
    public func pause() {
        objc_sync_enter(self)
        if state.isInProgress() && !paused {
            log(msg: "Pausing upgrade...", atLevel: .verbose)
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
            delegate?.upgradeStateDidChange(from: previousState, to: state)
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
            _ = imageManager.upload(data: imageData, delegate: self)
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
        setState(.success)
        objc_sync_enter(self)
        state = .none
        paused = false
        delegate?.upgradeDidComplete()
        // Release cyclic reference.
        cyclicReferenceHolder = nil
        objc_sync_exit(self)
    }
    
    private func fail(error: Error) {
        objc_sync_enter(self)
        log(msg: error.localizedDescription, atLevel: .error)
        let tmp = state
        state = .none
        paused = false
        delegate?.upgradeDidFail(inState: tmp, with: error)
        // Release cyclic reference.
        cyclicReferenceHolder = nil
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
    // MARK: - McuMgrCallbacks
    //**************************************************************************
    
    /// Callback for the VALIDATE state.
    ///
    /// This callback will fail the upgrade on error and continue to the next
    /// state on success.
    private lazy var validateCallback: McuMgrCallback<McuMgrImageStateResponse> =
    { [weak self] (response: McuMgrImageStateResponse?, error: Error?) in
        // Ensure the manager is not released.
        guard let self = self else {
            return
        }
        // Check for an error.
        if let error = error {
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Validation response is nil!"))
            return
        }
        self.log(msg: "Validation response: \(response)", atLevel: .verbose)
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
        
        // If the image in slot 1 is confirmed, we won't be able to erase or
        // test the slot. Therefore, we confirm the image in slot 0 to allow us
        // to modify the image in slot 1.
        if images.count > 1 && images[1].confirmed {
            self.validationConfirm(hash: images[0].hash)
            return
        }
        
        // If the image in slot 1 is pending, we won't be able to
        // erase or test the slot. Therefore, We must reset the device and
        // revalidate the new image state.
        if images.count > 1 && images[1].pending {
            self.defaultManager.transporter.addObserver(self)
            self.defaultManager.reset(callback: self.resetCallback)
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
            if images[1].permanent {
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
    
    func validationConfirm(hash: [UInt8]?) {
        self.imageManager.confirm(hash: hash) { [weak self] (response, error) in
            guard let self = self else {
                return
            }
            if let error = error {
                self.fail(error: error)
                return
            }
            guard let response = response else {
                self.fail(error: FirmwareUpgradeError.unknown("Test response is nil!"))
                return
            }
            if !response.isSuccess() {
                self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
                return
            }
            self.validate()
        }
    }
    
    /// Callback for the TEST state.
    ///
    /// This callback will fail the upgrade on error and continue to the next
    /// state on success.
    private lazy var testCallback: McuMgrCallback<McuMgrImageStateResponse> =
    { [weak self] (response: McuMgrImageStateResponse?, error: Error?) in
        // Ensure the manager is not released.
        guard let self = self else {
            return
        }
        // Check for an error.
        if let error = error {
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Test response is nil!"))
            return
        }
        self.log(msg: "Test response: \(response)", atLevel: .verbose)
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
    
    /// Callback for the RESET state.
    ///
    /// This callback will fail the upgrade on error. On success, the reset
    /// poller will be started after a 3 second delay.
    private lazy var resetCallback: McuMgrCallback<McuMgrResponse> =
    { [weak self] (response: McuMgrResponse?, error: Error?) in
        // Ensure the manager is not released.
        guard let self = self else {
            return
        }
        // Check for an error.
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
        self.resetResponseTime = Date()
        self.log(msg: "Reset request sent. Waiting for reset...", atLevel: .info)
    }
    
    public func transport(_ transport: McuMgrTransport, didChangeStateTo state: McuMgrTransportState) {
        transport.removeObserver(self)
        // Disregard connected state
        guard state == .disconnected else {
            return
        }
        self.log(msg: "Device has disconnected (reset). Reconnecting...", atLevel: .info)
        let timeSinceReset: TimeInterval
        if let resetResponseTime = resetResponseTime {
            let now = Date()
            timeSinceReset = now.timeIntervalSince(resetResponseTime)
        } else {
            // Fallback if state changed prior to `resetResponseTime` is set
            timeSinceReset = 0
        }
        let remainingTime = estimatedSwapTime - timeSinceReset
        
        if remainingTime > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                self?.reconnect()
            }
        } else {
            reconnect()
        }
    }
    
    /// Reconnect to the device and continue the
    private func reconnect() {
        imageManager.transporter.connect { [weak self] result in
            guard let self = self else {
                return
            }
            switch result {
            case .connected:
                self.log(msg: "Reconnect successful.", atLevel: .info)
                break
            case .deferred:
                self.log(msg: "Reconnect deferred.", atLevel: .info)
                break
            case .failed(let error):
                self.log(msg: "Reconnect failed. \(error)", atLevel: .error)
                self.fail(error: error)
                return
            }
            
            // Continue the upgrade after reconnect.
            switch self.state {
            case .validate:
                self.validate()
            case .reset:
                switch self.mode {
                case .testAndConfirm:
                    self.verify()
                default:
                    self.success()
                }
            default:
                break
            }
        }
    }
    
    private func log(msg: String, atLevel level: Log.Level) {
        Log.log(level, tag: TAG, msg: msg)
        delegate?.log(msg, atLevel: level)
    }
    
    /// Callback for the CONFIRM state.
    ///
    /// This callback will fail the upload on error or move to the next state on
    /// success.
    private lazy var confirmCallback: McuMgrCallback<McuMgrImageStateResponse> =
    { [weak self] (response: McuMgrImageStateResponse?, error: Error?) in
        // Ensure the manager is not released.
        guard let self = self else {
            return
        }
        // Check for an error.
        if let error = error {
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Confirm response is nil!"))
            return
        }
        self.log(msg: "Confirm response: \(response)", atLevel: .verbose)
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
// MARK: - ImageUploadDelegate
//******************************************************************************

extension FirmwareUpgradeManager: ImageUploadDelegate {
    
    public func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        delegate?.uploadProgressDidChange(bytesSent: bytesSent, imageSize: imageSize, timestamp: timestamp)
    }
    
    public func uploadDidFail(with error: Error) {
        // If the upload fails, fail the upgrade.
        fail(error: error)
    }
    
    public func uploadDidCancel() {
        delegate?.upgradeDidCancel(state: state)
        state = .none
        // Release cyclic reference.
        cyclicReferenceHolder = nil
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
// MARK: - FirmwareUpgradeError
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
            return "\(code)"
        case .connectionFailedAfterReset:
            return "Connection failed after reset"
        }
    }
}

//******************************************************************************
// MARK: - FirmwareUpgradeState
//******************************************************************************

public enum FirmwareUpgradeState {
    case none, validate, upload, test, reset, confirm, success
    
    func isInProgress() -> Bool {
        return self == .validate || self == .upload || self == .test
            || self == .reset || self == .confirm
    }
}

//******************************************************************************
// MARK: - FirmwareUpgradeMode
//******************************************************************************

public enum FirmwareUpgradeMode {
    /// When this mode is set, the manager will send the test and reset commands
    /// to the device after the upload is complete. The device will reboot and
    /// will run the new image on its next boot. If the new image supports
    /// auto-confirm feature, it will try to confirm itself and change state to
    /// permanent. If not, test image will run just once and will be swapped
    /// again with the original image on the next boot.
    ///
    /// Use this mode if you just want to test the image, when it can confirm
    /// itself.
    case testOnly
    
    /// When this flag is set, the manager will send confirm and reset commands
    /// immediately after upload.
    ///
    /// Use this mode if when the new image does not support both auto-confirm
    /// feature and SMP service and could not be confirmed otherwise.
    case confirmOnly
    
    /// When this flag is set, the manager will first send test followed by
    /// reset commands, then it will reconnect to the new application and will
    /// send confirm command.
    ///
    /// Use this mode when the new image supports SMP service and you want to
    /// test it before confirming.
    case testAndConfirm
}

//******************************************************************************
// MARK: - FirmwareUpgradeDelegate
//******************************************************************************

/// Callbacks for firmware upgrades started using FirmwareUpgradeManager.
public protocol FirmwareUpgradeDelegate : McuMgrLogDelegate {
    
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
