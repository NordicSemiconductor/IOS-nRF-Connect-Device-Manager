/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class FirmwareUpgradeManager : FirmwareUpgradeController, ConnectionObserver {
    private let imageManager: ImageManager
    private let defaultManager: DefaultManager
    private let basicManager: BasicManager
    private weak var delegate: FirmwareUpgradeDelegate?
    
    /// Cyclic reference is used to prevent from releasing the manager
    /// in the middle of an update. The reference cycle will be set
    /// when upgrade was started and released on success, error or cancel.
    private var cyclicReferenceHolder: (() -> FirmwareUpgradeManager)?
    
    private var i: Int!
    private var images: [FirmwareUpgradeImage]!
    private var eraseAppSettings: Bool!
    
    private var state: FirmwareUpgradeState
    private var paused: Bool = false
    
    /// Logger delegate may be used to obtain logs.
    public weak var logDelegate: McuMgrLogDelegate? {
        didSet {
            imageManager.logDelegate = logDelegate
            defaultManager.logDelegate = logDelegate
        }
    }
    
    /// Upgrade mode. The default mode is .confirmOnly.
    public var mode: FirmwareUpgradeMode = .confirmOnly
    
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
        self.basicManager = BasicManager(transporter: transporter)
        self.delegate = delegate
        self.state = .none
    }
    
    //**************************************************************************
    // MARK: Control Functions
    //**************************************************************************
    
    /// Start the firmware upgrade.
    ///
    /// Use this convenience call of ``start(images:erasingAppSettings:)`` if you're only
    /// updating the App Core (i.e. no Multi-Image).
    /// - parameter data: `Data` to upload to App Core (Image 0).
    /// - parameter eraseAppSettings: If enabled, after succesful upload but before test/confirm/reset phase, an Erase App Settings Command will be sent and awaited before proceeding.
    public func start(data: Data, erasingAppSettings eraseAppSettings: Bool = true) throws {
        try start(images: [(0, data)], erasingAppSettings: eraseAppSettings)
    }
    
    /// Start the firmware upgrade.
    ///
    /// This is the full-featured API to start DFU update, including support for Multi-Image uploads.
    /// - parameter images: An Array of (Image, `Data`) pairs with the Image Core/Index and its corresponding `Data` to upload.
    /// - parameter eraseAppSettings: If enabled, after succesful upload but before test/confirm/reset phase, an Erase App Settings Command will be sent and awaited before proceeding.
    public func start(images: [(Int, Data)], erasingAppSettings eraseAppSettings: Bool = true) throws {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        guard state == .none else {
            log(msg: "Firmware upgrade is already in progress", atLevel: .warning)
            return
        }
        
        i = 0
        self.images = try images.map { try FirmwareUpgradeImage($0) }
        self.eraseAppSettings = eraseAppSettings
        
        // Grab a strong reference to something holding a strong reference to self.
        cyclicReferenceHolder = { return self }
        
        let numberOfBytes = images.reduce(0, { $0 + $1.1.count })
        log(msg: "Upgrading with \(images.count) images in mode '\(mode)' (\(numberOfBytes) bytes)...",
            atLevel: .application)
        delegate?.upgradeDidStart(controller: self)
        validate()
    }
    
    public func cancel() {
        objc_sync_enter(self)
        if state == .upload {
            imageManager.cancelUpload()
            paused = false
            log(msg: "Upgrade cancelled", atLevel: .application)
        }
        objc_sync_exit(self)
    }
    
    public func pause() {
        objc_sync_enter(self)
        if state.isInProgress() && !paused {
            paused = true
            if state == .upload {
                imageManager.pauseUpload()
            }
            log(msg: "Upgrade paused", atLevel: .application)
        }
        objc_sync_exit(self)
    }
    
    public func resume() {
        objc_sync_enter(self)
        if paused {
            paused = false
            log(msg: "Upgrade resumed", atLevel: .application)
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
            let imagesToUpload = images
                .filter({ !$0.uploaded })
                .map({ ImageManager.Image($0.image, $0.data) })
            _ = imageManager.upload(images: imagesToUpload, delegate: self)
        }
    }
    
    private func test(_ image: FirmwareUpgradeImage) {
        setState(.test)
        if !paused {
            imageManager.test(hash: [UInt8](image.hash), callback: testCallback)
        }
    }
    
    private func confirm(_ image: FirmwareUpgradeImage) {
        setState(.confirm)
        if !paused {
            imageManager.confirm(hash: [UInt8](image.hash), callback: confirmCallback)
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
        defer {
            objc_sync_exit(self)
        }
        if !paused {
            switch state {
            case .validate:
                validate()
            case .upload:
                imageManager.continueUpload()
            case .test:
                guard let nextImageToTest = self.images.first(where: { !$0.tested }) else { return }
                test(nextImageToTest)
            case .reset:
                reset()
            case .confirm:
                guard let nextImageToConfirm = self.images.first(where: { !$0.confirmed }) else { return }
                confirm(nextImageToConfirm)
            default:
                break
            }
        }
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
        guard let self = self else { return }
        
        // Check for an error.
        if let error = error {
            self.fail(error: error)
            return
        }
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Validation response is nil!"))
            return
        }
        self.log(msg: "Validation response: \(response)", atLevel: .application)
        // Check for McuMgrReturnCode error.
        if !response.isSuccess() {
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        // Check that the image array exists.
        guard let responseImages = response.images, responseImages.count > 0 else {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }
        
        for j in 0..<self.images.count {
            self.i = j
            
            let primary: McuMgrImageStateResponse.ImageSlot! = responseImages.first(where: { $0.image == j && $0.slot == 0 })
            if primary != nil {
                if Data(primary.hash) == self.images[j].hash {
                    self.images[j].uploaded = true
                    self.log(msg: "Image \(j)'s primary slot is already uploaded. Skipping Image \(j).", atLevel: .application)
                    
                    if primary.confirmed {
                        // The new firmware is already active and confirmed.
                        // No need to do anything.
                        continue
                    } else {
                        // The new firmware is in test mode.
                        switch self.mode {
                        case .confirmOnly, .testAndConfirm:
                            self.confirm(self.images[j])
                            return
                        case .testOnly:
                            continue
                        }
                    }
                }
            }
            
            guard let secondary = responseImages.first(where: { $0.image == j && $0.slot == 1 }) else {
                continue
            }

            // Check if the firmware has already been uploaded.
            if Data(secondary.hash) == self.images[j].hash {
                // Firmware is identical to the one in slot 1. No need to send
                // anything.

                // If the test and confirm commands were not sent, proceed
                // with next state.
                if !secondary.pending {
                    switch self.mode {
                    case .testOnly, .testAndConfirm:
                        self.test(self.images[j])
                    case .confirmOnly:
                        self.confirm(self.images[j])
                    }
                    return
                }

                // If the image was already confirmed, reset (if confirm was
                // intended), or fail.
                if secondary.permanent {
                    switch self.mode {
                    case .confirmOnly, .testAndConfirm:
                        self.reset()
                    case .testOnly:
                        self.fail(error: FirmwareUpgradeError.unknown("Image \(j) already confirmed. Can't be tested!"))
                    }
                    return
                }

                // If image was not confirmed, but test command was sent,
                // confirm or reset.
                switch self.mode {
                case .confirmOnly:
                    self.confirm(self.images[j])
                    return
                case .testOnly, .testAndConfirm:
                    self.reset()
                    return
                }
            } else {
                // If the image in secondary slot is confirmed, we won't be able to erase or
                // test the slot. Therefore, we confirm the image in the core's primary slot
                // to allow us to modify the image in the secondary slot.
                if secondary.confirmed {
                    guard primary != nil else { continue }
                    self.validationConfirm(hash: primary.hash)
                    return
                }

                // If the image in secondary slot is pending, we won't be able to
                // erase or test the slot. Therefore, We must reset the device and
                // revalidate the new image state.
                if secondary.pending {
                    self.defaultManager.transporter.addObserver(self)
                    self.defaultManager.reset(callback: self.resetCallback)
                    return
                }
            }
        }
        
        guard !self.images.filter({ !$0.uploaded }).isEmpty else {
            // The new firmware is already active and confirmed.
            // No need to do anything.
            self.success()
            return
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
        self.log(msg: "Test response: \(response)", atLevel: .application)
        // Check for McuMgrReturnCode error.
        if !response.isSuccess() {
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        // Check that the image array exists.
        guard let responseImages = response.images else {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }

        // Check that we have the correct number of images in the responseImages array.
        guard responseImages.count >= self.images.count else {
            self.fail(error: FirmwareUpgradeError.unknown("Test response expected \(self.images.count) or more, but received \(responseImages.count) instead."))
            return
        }
        
        for j in 0..<self.images.count {
            // Check that the image in secondary slot is pending (i.e. test succeeded).
            guard let secondary = responseImages.first(where: { $0.image == j && $0.slot == 1 }) else {
                self.fail(error: FirmwareUpgradeError.unknown("Unable to find secondary slot for Image \(j) in Test Response."))
                return
            }
            
            guard secondary.pending else {
                // For every image we upload, we need to send it the TEST Command.
                guard self.images[j].tested else {
                    self.log(msg: "Image \(j) is not in Pending state. Sending TEST Command.", atLevel: .info)
                    self.test(self.images[j])
                    return
                }
                
                // If we've sent it the TEST Command, the secondary slot must be in pending state to pass test.
                self.fail(error: FirmwareUpgradeError.unknown("Image \(j) is not in a pending state."))
                return
            }
            self.images[j].tested = true
            self.log(msg: "Image \(j) is in Pending state.", atLevel: .info)
        }
        
        // Test image succeeded. Begin device reset.
        self.log(msg: "Test Succeeded. Proceeding with device reset.", atLevel: .application)
        self.reset()
    }
    
    /// Callback for Erase App Settings Command.
    private lazy var eraseAppSettingsCallback: McuMgrCallback<McuMgrResponse> = { [weak self] (response: McuMgrResponse?, error: Error?) in
        guard let self = self else { return }
        
        if let error = error {
            self.fail(error: error)
            return
        }
        
        guard let response = response else {
            self.fail(error: FirmwareUpgradeError.unknown("Erase App Settings Response was nil!"))
            return
        }
        
        // rc != 0 is expected, DFU should continue.
        guard response.isSuccess() || response.rc != 0 else {
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        
        self.log(msg: "Erase App Settings Succesful. Proceeding.", atLevel: .application)
        // Set to false so uploadDidFinish() doesn't loop forever.
        self.eraseAppSettings = false
        self.uploadDidFinish()
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
        self.log(msg: "Reset request sent. Waiting for reset...", atLevel: .application)
    }
    
    public func transport(_ transport: McuMgrTransport, didChangeStateTo state: McuMgrTransportState) {
        transport.removeObserver(self)
        // Disregard connected state.
        guard state == .disconnected else {
            return
        }
        self.log(msg: "Device has disconnected (reset). Reconnecting...", atLevel: .info)
        let timeSinceReset: TimeInterval
        if let resetResponseTime = resetResponseTime {
            let now = Date()
            timeSinceReset = now.timeIntervalSince(resetResponseTime)
        } else {
            // Fallback if state changed prior to `resetResponseTime` is set.
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
            case .deferred:
                self.log(msg: "Reconnect deferred.", atLevel: .info)
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
                    self.log(msg: "Upgrade complete", atLevel: .application)
                    self.success()
                }
            default:
                break
            }
        }
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
            self.fail(error: FirmwareUpgradeError.unknown("Confirmation response is nil!"))
            return
        }
        self.log(msg: "Confirmation response: \(response)", atLevel: .application)
        // Check for McuMgrReturnCode error.
        if !response.isSuccess() {
            self.fail(error: FirmwareUpgradeError.mcuMgrReturnCodeError(response.returnCode))
            return
        }
        // Check that the image array exists.
        guard let responseImages = response.images, responseImages.count > 0 else {
            self.fail(error: FirmwareUpgradeError.invalidResponse(response))
            return
        }
        
        for j in 0..<self.images.count {
            switch self.mode {
            case .confirmOnly:
                // The new image should be in slot 1.
                guard let secondary = responseImages.first(where: { $0.image == j && $0.slot == 1 }) else {
                    self.fail(error: FirmwareUpgradeError.invalidResponse(response))
                    return
                }
                
                // Check that the new image is in permanent state.
                guard secondary.permanent else {
                    guard self.images[j].confirmed else {
                        self.confirm(self.images[j])
                        return
                    }
                    
                    // If we've sent it the CONFIRM Command, the secondary slot must be in PERMANENT state.
                    self.fail(error: FirmwareUpgradeError.unknown("Image \(secondary.image) Slot \(secondary.slot) is not in a permanent state."))
                    return
                }
                self.images[j].confirmed = true
                
                if j == self.images.indices.last {
                    // Image was confirmed, reset the device.
                    self.log(msg: "Image \(secondary.image) was confirmed in Slot \(secondary.slot). Resetting device.", atLevel: .application)
                    self.reset()
                }
            case .testAndConfirm:
                if let primary = responseImages.first(where: { $0.image == j && $0.slot == 0 }) {
                    // If Primary is available, check that the upgrade image has successfully booted.
                    if Data(primary.hash) != self.images[j].hash {
                        self.fail(error: FirmwareUpgradeError.unknown("Device failed to boot into Image \(primary.image)."))
                        return
                    }
                    // Check that the new image is in confirmed state.
                    if !primary.confirmed {
                        self.fail(error: FirmwareUpgradeError.unknown("Image \(primary.image) is not in a confirmed state."))
                        return
                    }
                    self.images[j].confirmed = true
                } else {
                    self.log(msg: "Skipping Image \(j) hash verification since primary is not available.", atLevel: .info)
                }
                
                guard j == self.images.indices.last else { continue }
                // Confirm successful.
                self.log(msg: "Upgrade complete.", atLevel: .application)
                self.success()
            case .testOnly:
                // Impossible state. Ignore.
                break
            }
        }
    }
}

private extension FirmwareUpgradeManager {
    
    func log(msg: String, atLevel level: McuMgrLogLevel) {
        logDelegate?.log(msg, ofCategory: .dfu, atLevel: level)
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
        // Before we can move on, we must check whether the user requested for App Core Settings
        // to be erased.
        if eraseAppSettings {
            log(msg: "'Erase App Settings' Enabled. Sending command...", atLevel: .info)
            basicManager.eraseAppSettings(callback: eraseAppSettingsCallback)
            return
        }
        
        // If eraseAppSettings command was sent or was not requested, we can continue.
        switch mode {
        case .confirmOnly:
            guard let firstUnconfirmedImage = self.images.first(where: { !$0.confirmed }) else {
                log(msg: "No images to confirm in \(#function).", atLevel: .warning)
                return
            }
            confirm(firstUnconfirmedImage)
        case .testOnly, .testAndConfirm:
            guard let firstUntestedImage = self.images.first(where: { !$0.tested }) else {
                log(msg: "No images to test in \(#function).", atLevel: .warning)
                return
            }
            test(firstUntestedImage)
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

extension FirmwareUpgradeError: LocalizedError {
    
    public var errorDescription: String? {
        switch self {
        case .unknown(let message):
            return message
        case .invalidResponse(let response):
            return "Invalid response: \(response)."
        case .mcuMgrReturnCodeError(let code):
            return "Remote error: \(code)."
        case .connectionFailedAfterReset:
            return "Connection failed after reset."
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
public protocol FirmwareUpgradeDelegate: AnyObject {
    
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

// MARK: - FirmwareUpgradeImage

fileprivate struct FirmwareUpgradeImage {
    
    // MARK: Properties
    
    let image: Int
    let data: Data
    let hash: Data
    var uploaded: Bool
    var tested: Bool
    var confirmed: Bool
    
    // MARK: Init
    
    init(_ image: (index: Int, data: Data)) throws {
        self.image = image.index
        self.data = image.data
        self.hash = try McuMgrImage(data: image.data).hash
        self.uploaded = false
        self.tested = false
        self.confirmed = false
    }
}

// MARK: - FirmwareUpgradeImage Hashable

extension FirmwareUpgradeImage: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(image)
        hasher.combine(hash)
    }
}
