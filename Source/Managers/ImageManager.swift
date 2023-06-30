/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth
import SwiftCBOR

public class ImageManager: McuManager {
    public typealias Image = (image: Int, data: Data)
    
    override class var TAG: McuMgrLogCategory { .image }
    
    private static let PIPELINED_WRITES_TIMEOUT_SECONDS = 10
    
    // MARK: - IDs

    enum ImageID: UInt8 {
        case State = 0
        case Upload = 1
        case File = 2
        case CoreList = 3
        case CoreLoad = 4
        case Erase = 5
        case EraseState = 6
    }
    
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
        send(op: .read, commandId: ImageID.State, payload: nil, callback: callback)
    }
    
    /// Sends the next packet of data from given offset.
    /// To send a complete image, use upload(data:image:delegate) method instead.
    ///
    /// - parameter data: The image data.
    /// - parameter image: The image number / slot number for DFU.
    /// - parameter offset: The offset from which this data will be sent.
    /// - parameter alignment: The byte alignment to apply to the data (if any).
    /// - parameter callback: The callback.
    public func upload(data: Data, image: Int, offset: UInt64, alignment: ImageUploadAlignment,
                       callback: @escaping McuMgrCallback<McuMgrUploadResponse>) {
        let payloadLength = maxDataPacketLengthFor(data: data, image: image, offset: offset)
        
        let chunkOffset = offset
        let chunkEnd = min(chunkOffset + payloadLength, UInt64(data.count))
        var payload: [String:CBOR] = ["data": CBOR.byteString([UInt8](data[chunkOffset..<chunkEnd])),
                                      "off": CBOR.unsignedInt(chunkOffset)]
        let uploadTimeoutInSeconds: Int
        if chunkOffset == 0 {
            // 0 is Default behaviour, so we can ignore adding it and
            // the firmware will do the right thing.
            if image > 0 {
                payload.updateValue(CBOR.unsignedInt(UInt64(image)), forKey: "image")
            }
            
            payload.updateValue(CBOR.unsignedInt(UInt64(data.count)), forKey: "len")
            payload.updateValue(CBOR.byteString([UInt8](data.sha256())), forKey: "sha")
            
            // When uploading offset 0, we might trigger an erase on the firmware's end.
            // Hence, the longer timeout.
            uploadTimeoutInSeconds = McuManager.DEFAULT_SEND_TIMEOUT_SECONDS
        } else {
            uploadTimeoutInSeconds = McuManager.FAST_TIMEOUT
        }
        send(op: .write, commandId: ImageID.Upload, payload: payload, timeout: uploadTimeoutInSeconds,
             callback: callback)
        uploadExpectedOffsets.append(chunkEnd)
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
        send(op: .write, commandId: ImageID.State, payload: payload, callback: callback)
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
        send(op: .write, commandId: ImageID.State, payload: payload, callback: callback)
    }
    
    /// Begins the image upload to a peripheral.
    ///
    /// An instance of ImageManager can only have one upload in progress at a
    /// time, but we support uploading multiple images in a single call. If
    /// this method is called multiple times on the same ImageManager instance,
    /// all calls after the first will return false. Upload progress is reported
    /// asynchronously to the delegate provided in this method.
    ///
    /// - parameter images: The images to upload.
    /// - parameter configuration: The parameters used during the upgrade process. Set with defaults if not provided.
    /// - parameter delegate: The delegate to recieve progress callbacks.
    ///
    /// - returns: True if the upload has started successfully, false otherwise.
    public func upload(images: [Image], using configuration: FirmwareUpgradeConfiguration = FirmwareUpgradeConfiguration(),
                       delegate: ImageUploadDelegate?) -> Bool {
        // Make sure two uploads cant start at once.
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        // If upload is already in progress or paused, do not continue.
        if uploadState == .none {
            // Set upload flag to true.
            uploadState = .uploading
        } else {
            log(msg: "An image upload is already in progress", atLevel: .warning)
            return false
        }
        
        guard let firstImage = images.first else {
            log(msg: "Nothing to upload", atLevel: .warning)
            return false
        }
        
        // Set upload delegate.
        uploadDelegate = delegate
        
        uploadImages = images
        
        // Set image data.
        imageData = firstImage.data
        
        // Set the slot we're uploading the image to.
        // Grab a strong reference to something holding a strong reference to self.
        cyclicReferenceHolder = { return self }
        uploadIndex = 0
        uploadExpectedOffsets = []
        uploadLastOffset = 0
        // Note that pipelining requires the use of byte-alignment, otherwise we
        // can't predict how many bytes the firmware will accept in each chunk.
        uploadConfiguration = configuration
        if let bleTransport = transporter as? McuMgrBleTransport {
            bleTransport.numberOfParallelWrites = configuration.pipelineDepth
            bleTransport.chunkSendDataToMtuSize = configuration.reassemblyBufferSize != 0
        }
        
        log(msg: "Uploading image \(firstImage.image) (\(firstImage.data.count) bytes)...", atLevel: .verbose)
        upload(data: firstImage.data, image: firstImage.image, offset: 0,
               alignment: configuration.byteAlignment,
               callback: uploadCallback)
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
        send(op: .write, commandId: ImageID.Erase, payload: nil, callback: callback)
    }
    
    /// Erases the state of the secondary image slot on the device.
    ///
    /// - parameter callback: The response callback.
    public func eraseState(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ImageID.EraseState, payload: nil, callback: callback)
    }

    /// Requst core dump on the device. The data will be stored in the dump
    /// area.
    ///
    /// - parameter callback: The response callback.
    public func coreList(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .read, commandId: ImageID.CoreList, payload: nil, callback: callback)
    }
    
    /// Read core dump from the given offset.
    ///
    /// - parameter offset: The offset to load from, in bytes.
    /// - parameter callback: The response callback.
    public func coreLoad(offset: UInt, callback: @escaping McuMgrCallback<McuMgrCoreLoadResponse>) {
        let payload: [String:CBOR] = ["off": CBOR.unsignedInt(UInt64(offset))]
        send(op: .read, commandId: ImageID.CoreLoad, payload: payload, callback: callback)
    }

    /// Erase the area if it has a core dump, or the header is empty.
    ///
    /// - parameter callback: The response callback.
    public func coreErase(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ImageID.CoreLoad, payload: nil, callback: callback)
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
    
    /// Contains the current Image's data to send to the device.
    private var imageData: Data?
    /// Image 'slot' or core of the device we're sending data to.
    /// Default value, will be secondary slot of core 0.
    private var uploadIndex: Int = 0
    /// Current image byte offset to send from.
    private var uploadLastOffset: UInt64!
    
    private var uploadExpectedOffsets: [UInt64] = []
    /// The sequence of images we want to send to the device.
    private var uploadImages: [Image]?
    /// Delegate to send image upload updates to.
    private weak var uploadDelegate: ImageUploadDelegate?
    /// Groups multiple Settings regarding DFU Upload, such as enabling Pipelining,
    /// Byte Alignment and/or SMP Reassembly.
    private var uploadConfiguration: FirmwareUpgradeConfiguration!
    
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
            let image: Int! = self.uploadImages?[uploadIndex].image
            uploadState = .uploading
            let offset = uploadLastOffset ?? 0
            log(msg: "Resuming uploading image \(image) from \(offset)/\(imageData.count)...", atLevel: .application)
            upload(data: imageData, image: image, offset: offset, alignment: uploadConfiguration.byteAlignment,
                   callback: uploadCallback)
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
        
        if #available(iOS 10.0, watchOS 3.0, *) {
            dispatchPrecondition(condition: .onQueue(.main))
        }
        
        // Check for an error.
        if let error = error {
            if case let McuMgrTransportError.insufficientMtu(newMtu) = error {
                do {
                    try self.setMtu(newMtu)
                    self.restartUpload()
                } catch let mtuResetError {
                    self.cancelUpload(error: mtuResetError)
                }
                return
            }
            self.cancelUpload(error: error)
            return
        }
        
        // If response includes 'match' value, it should be true.
        // Else, we assume everything is OK.
        guard response?.match ?? true else {
            self.cancelUpload(error: ImageUploadError.offsetMismatch)
            return
        }
        
        // Make sure the image data is set.
        guard let currentImageData = self.imageData, let images = self.uploadImages else {
            self.cancelUpload(error: ImageUploadError.invalidData)
            return
        }
        // Make sure the response is not nil.
        guard let response = response else {
            self.cancelUpload(error: ImageUploadError.invalidPayload)
            return
        }
        
        guard response.isSuccess() else {
            self.cancelUpload(error: ImageUploadError.mcuMgrErrorCode(response.returnCode))
            return
        }
        
        if let offset = response.off {
            // We expect In-Order Responses.
            if self.uploadExpectedOffsets.contains(offset) {
                self.uploadLastOffset = max(self.uploadLastOffset, UInt64(offset))
            } else {
                // Offset Mismatch.
                self.uploadLastOffset = offset
                
                if !self.uploadExpectedOffsets.isEmpty {
                    self.uploadExpectedOffsets.removeFirst()
                }
                
                // All of our previous 'sends' are invalid.
                // Wait for all of them to return and then continue.
                guard self.uploadExpectedOffsets.isEmpty else {
                    return
                }
                print("Extinguisied pending writes.")
            }
            self.uploadExpectedOffsets.removeAll(where: { $0 <= offset })
            
            self.uploadDelegate?.uploadProgressDidChange(bytesSent: Int(self.uploadLastOffset), imageSize: currentImageData.count, timestamp: Date())
            self.log(msg: "Response Offset: \(offset), UploadOffset: \(self.uploadLastOffset), Pending Offsets: \(self.uploadExpectedOffsets.map({ $0 })), ",
                     atLevel: .debug)
            
            if self.uploadState == .none {
                self.log(msg: "Upload cancelled", atLevel: .application)
                self.resetUploadVariables()
                self.uploadDelegate?.uploadDidCancel()
                self.uploadDelegate = nil
                // Release cyclic reference.
                self.cyclicReferenceHolder = nil
                return
            }
            
            guard self.uploadState == .uploading else { return }
            
            // Check if the upload has completed.
            if offset == currentImageData.count {
                if self.uploadIndex == images.count - 1 {
                    self.log(msg: "Upload finished (\(self.uploadIndex + 1) of \(images.count))", atLevel: .application)
                    self.resetUploadVariables()
                    self.uploadDelegate?.uploadDidFinish()
                    self.uploadDelegate = nil
                    // Release cyclic reference.
                    self.cyclicReferenceHolder = nil
                } else {
                    self.log(msg: "Uploaded image \(images[self.uploadIndex].image) (\(self.uploadIndex + 1) of \(images.count))", atLevel: .application)
                    
                    // Don't trigger writes to another image unless all write(s) have returned for
                    // the current one.
                    guard self.uploadExpectedOffsets.isEmpty else {
                        return
                    }
                    
                    // Move on to the next image.
                    self.uploadIndex += 1
                    self.uploadLastOffset = 0
                    self.imageData = images[self.uploadIndex].data
                    self.log(msg: "Uploading image \(images[self.uploadIndex].image) (\(self.imageData?.count) bytes)...", atLevel: .application)
                    self.uploadDelegate?.uploadProgressDidChange(bytesSent: 0, imageSize: images[self.uploadIndex].data.count, timestamp: Date())
                    self.sendNext(from: UInt64(0))
                }
                return
            }
            
            let currentImageDataSize = self.imageData?.count ?? 0
            for i in 0..<(self.uploadConfiguration.pipelineDepth - self.uploadExpectedOffsets.count) {
                guard let chunkOffset = self.uploadExpectedOffsets.last ?? self.uploadLastOffset,
                      chunkOffset < currentImageData.count else {
                    
                    // No remaining chunks to be sent?
                    self.log(msg: "No remaining chunks to be sent? chunkOffset: \(self.uploadExpectedOffsets.last ?? self.uploadLastOffset), imageData: \(currentImageDataSize).", atLevel: .warning)
                    return
                }
                self.sendNext(from: chunkOffset)
            }
        } else {
            self.cancelUpload(error: ImageUploadError.invalidPayload)
        }
    }
    
    private func sendNext(from offset: UInt64) {
        let imageData: Data! = self.uploadImages?[uploadIndex].data
        let imageSlot: Int! = self.uploadImages?[uploadIndex].image
        upload(data: imageData, image: imageSlot, offset: offset,
               alignment: uploadConfiguration.byteAlignment,
               callback: uploadCallback)
    }
    
    private func resetUploadVariables() {
        objc_sync_enter(self)
        // Reset upload state.
        uploadState = .none
        
        // Deallocate and nil image data pointers.
        imageData = nil
        uploadImages = nil
        
        // Reset upload vars.
        uploadIndex = 0
        uploadExpectedOffsets = []
        objc_sync_exit(self)
    }
    
    private func restartUpload() {
        objc_sync_enter(self)
        guard let uploadImages = uploadImages, let uploadDelegate = uploadDelegate else {
            log(msg: "Could not restart upload: image data or callback is null", atLevel: .error)
            return
        }
        let tempUploadImages = uploadImages
        let tempUploadIndex = uploadIndex
        let tempDelegate = uploadDelegate
        resetUploadVariables()
        let remainingImages = tempUploadImages.filter({ $0.image >= tempUploadIndex })
        _ = upload(images: remainingImages, using: uploadConfiguration, delegate: tempDelegate)
        objc_sync_exit(self)
    }
    
    private func maxDataPacketLengthFor(data: Data, image: Int, offset: UInt64) -> UInt64 {
        guard offset < data.count else { return UInt64(McuMgrHeader.HEADER_LENGTH) }
        
        let remainingBytes = UInt64(data.count) - offset
        let packetOverhead = calculatePacketOverhead(data: data, image: image, offset: UInt64(offset))
        let maxPacketSize = max(uploadConfiguration.reassemblyBufferSize, UInt64(mtu))
        var maxDataLength = maxPacketSize - UInt64(packetOverhead)
        if uploadConfiguration.byteAlignment != .disabled {
            maxDataLength = (maxDataLength / uploadConfiguration.byteAlignment.rawValue) * uploadConfiguration.byteAlignment.rawValue
        }
        return min(maxDataLength, remainingBytes)
    }
    
    private func calculatePacketOverhead(data: Data, image: Int, offset: UInt64) -> Int {
        // Get the Mcu Manager header.
        var payload: [String:CBOR] = ["data": CBOR.byteString([UInt8]([0])),
                                      "off":  CBOR.unsignedInt(offset)]
        // If this is the initial packet we have to include the length of the
        // entire image.
        if offset == 0 {
            if image > 0 {
                payload.updateValue(CBOR.unsignedInt(UInt64(image)), forKey: "image")
            }
            
            payload.updateValue(CBOR.unsignedInt(UInt64(data.count)), forKey: "len")
            payload.updateValue(CBOR.byteString([UInt8](data.sha256())), forKey: "sha")
        }
        // Build the packet and return the size.
        let packet = McuManager.buildPacket(scheme: transporter.getScheme(), op: .write, flags: 0,
                                            group: group.uInt16Value, sequenceNumber: 0, commandId: ImageID.Upload,
                                            payload: payload)
        var packetOverhead = packet.count + 5
        if transporter.getScheme().isCoap() {
            // Add 25 bytes to packet overhead estimate for the CoAP header.
            packetOverhead = packetOverhead + 25
        }
        return packetOverhead
    }
}

// MARK: - ImageUploadAlignment

public enum ImageUploadAlignment: UInt64, Codable, CaseIterable, CustomStringConvertible {
    
    case disabled = 0
    case twoByte = 2
    case fourByte = 4
    case eightByte = 8
    case sixteenByte = 16
    
    public var description: String {
        guard self != .disabled else { return "Disabled" }
        return "\(rawValue)-Byte"
    }
}

// MARK: - ImageUploadError

public enum ImageUploadError: Error {
    /// Response payload values do not exist.
    case invalidPayload
    /// Image Data is nil.
    case invalidData
    /// Response payload reports package offset does not match expected value.
    case offsetMismatch
    
    case invalidUploadSequenceNumber(McuSequenceNumber)
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
        case .offsetMismatch:
            return "Response payload reports package offset does not match expected value."
        case .invalidUploadSequenceNumber(let sequenceNumber):
            return "Received Response for Unknown Sequence Number \(sequenceNumber)."
        case .mcuMgrErrorCode(let code):
            return "Remote error: \(code)"
        }
    }
}

//******************************************************************************
// MARK: Image Upload Delegate
//******************************************************************************

public protocol ImageUploadDelegate: AnyObject {
    
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

