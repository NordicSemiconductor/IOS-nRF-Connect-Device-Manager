/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth
import SwiftCBOR

public class ImageManager: McuManager {
    override class var TAG: McuMgrLogCategory { .image }
    
    private static let truncatedHashLen = 3
    
    //**************************************************************************
    // MARK: Constants
    //**************************************************************************

    // Mcu Image Manager command IDs.
    let ID_STATE       = UInt8(0)
    let ID_UPLOAD      = UInt8(1)
    let ID_FILE        = UInt8(2)
    let ID_CORELIST    = UInt8(3)
    let ID_CORELOAD    = UInt8(4)
    let ID_ERASE       = UInt8(5)
    let ID_ERASE_STATE = UInt8(6)
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: McuMgrGroup.image, transporter: transporter)
    }
    
    //**************************************************************************
    // MARK: Commands
    //**************************************************************************

    /// List the images on the device.
    ///
    /// - parameter callback: The response callback.
    public func list(callback: @escaping McuMgrCallback<McuMgrImageStateResponse>) {
        send(op: .read, commandId: ID_STATE, payload: nil, callback: callback)
    }
    
    /// Sends the next packet of data from given offset.
    /// To send a complete image, use upload(data:delegate) method instead.
    ///
    /// - parameter data: The image data.
    /// - parameter offset: The offset from this data will be sent.
    /// - parameter callback: The callback.
    public func upload(data: Data, offset: UInt, callback: @escaping McuMgrCallback<McuMgrUploadResponse>) {
        // Calculate the number of remaining bytes.
        let remainingBytes: UInt = UInt(data.count) - offset
        
        // Data length to end is the minimum of the max data lenght and the
        // number of remaining bytes.
        let packetOverhead = calculatePacketOverhead(data: data, offset: UInt64(offset))
        
        // Get the length of image data to send.
        let maxDataLength: UInt = UInt(mtu) - UInt(packetOverhead)
        let dataLength: UInt = min(maxDataLength, remainingBytes)
        
        // Build the request payload.
        var payload: [String:CBOR] = ["data": CBOR.byteString([UInt8](data[offset..<(offset+dataLength)])),
                                      "off": CBOR.unsignedInt(UInt64(offset))]
        
        // If this is the initial packet, send the image data length and
        // SHA 256 in the payload.
        if offset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt64(data.count)), forKey: "len")
            payload.updateValue(CBOR.byteString([UInt8](data.sha256()[0..<ImageManager.truncatedHashLen])), forKey: "sha")
        }
        // Build request and send.
        send(op: .write, commandId: ID_UPLOAD, payload: payload, callback: callback)
    }
    
    /// Test the image with the provided hash.
    ///
    /// A successful test will put the image in a pending state. A pending image
    /// will be booted upon once upon reset, but not again unless confirmed.
    ///
    /// - parameter hash: The hash of the image to test.
    /// - parameter callback: The response callback.
    public func test(hash: [UInt8], callback: @escaping McuMgrCallback<McuMgrImageStateResponse>) {
        let payload: [String:CBOR] = ["hash": CBOR.byteString(hash),
                                      "confirm": CBOR.boolean(false)]
        send(op: .write, commandId: ID_STATE, payload: payload, callback: callback)
    }
    
    /// Confirm the image with the provided hash.
    ///
    /// A successful confirm will make the image permenant (i.e. the image will
    /// be booted upon reset).
    ///
    /// - parameter hash: The hash of the image to confirm. If not provided, the
    ///   current image running on the device will be made permenant.
    /// - parameter callback: The response callback.
    public func confirm(hash: [UInt8]? = nil, callback: @escaping McuMgrCallback<McuMgrImageStateResponse>) {
        var payload: [String:CBOR] = ["confirm": CBOR.boolean(true)]
        if let hash = hash {
            payload.updateValue(CBOR.byteString(hash), forKey: "hash")
        }
        send(op: .write, commandId: ID_STATE, payload: payload, callback: callback)
    }
    
    /// Begins the image upload to a peripheral.
    ///
    /// An instance of ImageManager can only have one upload in progress at a
    /// time. Therefore, if this method is called multiple times on the same
    /// ImageManager instance, all calls after the first will return false.
    /// Upload progress is reported asynchronously to the delegate provided in
    /// this method.
    ///
    /// - parameter data: The entire image data to be uploaded to the peripheral.
    /// - parameter delegate: The delegate to recieve progress callbacks.
    ///
    /// - returns: True if the upload has started successfully, false otherwise.
    public func upload(data: Data, delegate: ImageUploadDelegate?) -> Bool {
        // Make sure two uploads cant start at once.
        objc_sync_enter(self)
        // If upload is already in progress or paused, do not continue.
        if uploadState == .none {
            // Set upload flag to true.
            uploadState = .uploading
        } else {
            log(msg: "An image upload is already in progress", atLevel: .warning)
            objc_sync_exit(self)
            return false
        }
        objc_sync_exit(self)
        
        // Set upload delegate.
        uploadDelegate = delegate
        
        // Set image data.
        imageData = data
        
        // Grab a strong reference to something holding a strong reference to self.
        cyclicReferenceHolder = { return self }
        
        log(msg: "Uploading image (\(data.count) bytes)...", atLevel: .application)
        upload(data: imageData!, offset: 0, callback: uploadCallback)
        return true
    }

    /// Erases an unused image from the secondary image slot on the device.
    ///
    /// The image cannot be erased if the image is a confirmed image, is marked
    /// for test on the next reboot, or is an active image for a split image
    /// setup.
    ///
    /// - parameter callback: The response callback.
    public func erase(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID_ERASE, payload: nil, callback: callback)
    }
    
    /// Erases the state of the secondary image slot on the device.
    ///
    /// - parameter callback: The response callback.
    public func eraseState(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID_ERASE_STATE, payload: nil, callback: callback)
    }

    /// Requst core dump on the device. The data will be stored in the dump
    /// area.
    ///
    /// - parameter callback: The response callback.
    public func coreList(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .read, commandId: ID_CORELIST, payload: nil, callback: callback)
    }
    
    /// Read core dump from the given offset.
    ///
    /// - parameter offset: The offset to load from, in bytes.
    /// - parameter callback: The response callback.
    public func coreLoad(offset: UInt, callback: @escaping McuMgrCallback<McuMgrCoreLoadResponse>) {
        let payload: [String:CBOR] = ["off": CBOR.unsignedInt(UInt64(offset))]
        send(op: .read, commandId: ID_CORELOAD, payload: payload, callback: callback)
    }

    /// Erase the area if it has a core dump, or the header is empty.
    ///
    /// - parameter callback: The response callback.
    public func coreErase(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID_CORELOAD, payload: nil, callback: callback)
    }
    
    //**************************************************************************
    // MARK: Image Upload
    //**************************************************************************

    /// Image upload states
    public enum UploadState: UInt8 {
        case none      = 0
        case uploading = 1
        case paused    = 2
    }
    
    /// State of the image upload.
    private var uploadState: UploadState = .none
    /// Current image byte offset to send from.
    private var offset: UInt64 = 0
    
    /// Contains the image data to send to the device.
    private var imageData: Data?
    /// Delegate to send image upload updates to.
    private weak var uploadDelegate: ImageUploadDelegate?
    
    /// Cyclic reference is used to prevent from releasing the manager
    /// in the middle of an update. The reference cycle will be set
    /// when upload was started and released on success, error or cancel.
    private var cyclicReferenceHolder: (() -> ImageManager)?
    
    /// Cancels the current upload.
    ///
    /// If an error is supplied, the delegate's didFailUpload method will be
    /// called with the Upload Error provided.
    ///
    /// - parameter error: The optional upload error which caused the
    ///   cancellation. This error (if supplied) is used as the argument for the
    ///   delegate's didFailUpload method.
    public func cancelUpload(error: Error? = nil) {
        objc_sync_enter(self)
        if uploadState == .none {
            log(msg: "Image upload is not in progress", atLevel: .warning)
        } else {
            if let error = error {
                resetUploadVariables()
                uploadDelegate?.uploadDidFail(with: error)
                uploadDelegate = nil
                log(msg: "Upload cancelled due to error: \(error)", atLevel: .error)
                // Release cyclic reference.
                cyclicReferenceHolder = nil
            } else {
                if uploadState == .paused {
                    resetUploadVariables()
                    uploadDelegate?.uploadDidCancel()
                    uploadDelegate = nil
                    log(msg: "Upload cancelled", atLevel: .application)
                    // Release cyclic reference.
                    cyclicReferenceHolder = nil
                }
                // else
                // Transfer will be cancelled after the next notification is received.
            }
            uploadState = .none
        }
        objc_sync_exit(self)
    }
    
    /// Pauses the current upload. If there is no upload in progress, nothing
    /// happens.
    public func pauseUpload() {
        objc_sync_enter(self)
        if uploadState == .none {
            log(msg: "Upload is not in progress and therefore cannot be paused", atLevel: .warning)
        } else {
            uploadState = .paused
            log(msg: "Upload paused", atLevel: .application)
        }
        objc_sync_exit(self)
    }

    /// Continues a paused upload. If the upload is not paused or not uploading,
    /// nothing happens.
    public func continueUpload() {
        objc_sync_enter(self)
        guard let imageData = imageData else {
            objc_sync_exit(self)
            if uploadState != .none {
                cancelUpload(error: ImageUploadError.invalidData)
            }
            return
        }
        if uploadState == .paused {
            log(msg: "Continuing upload from \(offset)/\(imageData.count)...", atLevel: .application)
            uploadState = .uploading
            upload(data: imageData, offset: UInt(offset), callback: uploadCallback)
        } else {
            log(msg: "Upload has not been previously paused", atLevel: .warning)
        }
        objc_sync_exit(self)
    }
    
    // MARK: - Image Upload Private Methods
    
    private lazy var uploadCallback: McuMgrCallback<McuMgrUploadResponse> = {
        [weak self] (response: McuMgrUploadResponse?, error: Error?) in
        // Ensure the manager is not released.
        guard let self = self else {
            return
        }
        // Check for an error.
        if let error = error {
            if case let McuMgrTransportError.insufficientMtu(newMtu) = error {
                if !self.setMtu(newMtu) {
                    self.cancelUpload(error: error)
                } else {
                    self.restartUpload()
                }
                return
            }
            self.cancelUpload(error: error)
            return
        }
        // Make sure the image data is set.
        guard let imageData = self.imageData else {
            self.cancelUpload(error: ImageUploadError.invalidData)
            return
        }
        // Make sure the response is not nil.
        guard let response = response else {
            self.cancelUpload(error: ImageUploadError.invalidPayload)
            return
        }
        // Check for an error return code.
        guard response.isSuccess() else {
            self.cancelUpload(error: ImageUploadError.mcuMgrErrorCode(response.returnCode))
            return
        }
        // Get the offset from the response.
        if let offset = response.off {
            // Set the image upload offset.
            self.offset = offset
            self.uploadDelegate?.uploadProgressDidChange(bytesSent: Int(offset), imageSize: imageData.count, timestamp: Date())
            
            if self.uploadState == .none {
                self.log(msg: "Upload cancelled", atLevel: .application)
                self.resetUploadVariables()
                self.uploadDelegate?.uploadDidCancel()
                self.uploadDelegate = nil
                // Release cyclic reference.
                self.cyclicReferenceHolder = nil
                return
            }
            
            // Check if the upload has completed.
            if offset == imageData.count {
                self.log(msg: "Upload finished", atLevel: .application)
                self.resetUploadVariables()
                self.uploadDelegate?.uploadDidFinish()
                self.uploadDelegate = nil
                // Release cyclic reference.
                self.cyclicReferenceHolder = nil
                return
            }
            
            // Send the next packet of data.
            self.sendNext(from: UInt(offset))
        } else {
            self.cancelUpload(error: ImageUploadError.invalidPayload)
        }
    }
    
    private func sendNext(from offset: UInt) {
        if uploadState != .uploading {
            return
        }
        upload(data: imageData!, offset: offset, callback: uploadCallback)
    }
    
    private func resetUploadVariables() {
        objc_sync_enter(self)
        // Reset upload state.
        uploadState = .none
        
        // Deallocate and nil image data pointers.
        imageData = nil
        
        // Reset upload vars.
        offset = 0
        objc_sync_exit(self)
    }
    
    private func restartUpload() {
        objc_sync_enter(self)
        guard let imageData = imageData, let uploadDelegate = uploadDelegate else {
            log(msg: "Could not restart upload: image data or callback is null", atLevel: .error)
            return
        }
        let tempData = imageData
        let tempDelegate = uploadDelegate
        resetUploadVariables()
        _ = upload(data: tempData, delegate: tempDelegate)
        objc_sync_exit(self)
    }
    
    private func calculatePacketOverhead(data: Data, offset: UInt64) -> Int {
        // Get the Mcu Manager header.
        var payload: [String:CBOR] = ["data": CBOR.byteString([UInt8]([0])),
                                      "off":  CBOR.unsignedInt(offset)]
        // If this is the initial packet we have to include the length of the
        // entire image.
        if offset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt64(data.count)), forKey: "len")
            payload.updateValue(CBOR.byteString([UInt8](repeating: 0, count: ImageManager.truncatedHashLen)), forKey: "sha")
        }
        // Build the packet and return the size.
        let packet = McuManager.buildPacket(scheme: transporter.getScheme(), op: .write, flags: 0,
                                            group: group.uInt16Value, sequenceNumber: 0, commandId: ID_UPLOAD, payload: payload)
        var packetOverhead = packet.count + 5
        if transporter.getScheme().isCoap() {
            // Add 25 bytes to packet overhead estimate for the CoAP header.
            packetOverhead = packetOverhead + 25
        }
        return packetOverhead
    }
}

public enum ImageUploadError: Error {
    /// Response payload values do not exist.
    case invalidPayload
    /// Image Data is nil.
    case invalidData
    /// McuMgrResponse contains a error return code.
    case mcuMgrErrorCode(McuMgrReturnCode)
}

extension ImageUploadError: LocalizedError {
    
    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Response payload values do not exist."
        case .invalidData:
            return "Image data is nil."
        case .mcuMgrErrorCode(let code):
            return "Remote error: \(code)."
        }
    }
    
}

//******************************************************************************
// MARK: Image Upload Delegate
//******************************************************************************

public protocol ImageUploadDelegate : class {
    
    /// Called when a packet of image data has been sent successfully.
    ///
    /// - parameter bytesSent: The total number of image bytes sent so far.
    /// - parameter imageSize: The overall size of the image being uploaded.
    /// - parameter timestamp: The time this response packet was received.
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date)

    /// Called when an image upload has failed.
    ///
    /// - parameter error: The error that caused the upload to fail.
    func uploadDidFail(with error: Error)
    
    /// Called when the upload has been cancelled.
    func uploadDidCancel()

    /// Called when the upload has finished successfully.
    func uploadDidFinish()
}

