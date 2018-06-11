/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class ImageManager: McuManager {
    
    //*******************************************************************************************
    // MARK: Constants
    //*******************************************************************************************

    // Image command IDs
    let ID_STATE = UInt8(0)
    let ID_UPLOAD = UInt8(1)
    let ID_FILE = UInt8(2)
    let ID_CORELIST = UInt8(3)
    let ID_CORELOAD = UInt8(4)
    let ID_ERASE = UInt8(5)
    
    //*******************************************************************************************
    // MARK: Initializers
    //*******************************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: .image, transporter: transporter)
    }
    
    //*******************************************************************************************
    // MARK: Commands
    //*******************************************************************************************

    /// List the images on the device
    ///
    /// - parameter callback: The response callback
    public func list(callback: @escaping McuMgrCallback<McuMgrImageStateResponse>) {
        send(op: .read, commandId: ID_STATE, payload: nil, callback: callback)
    }
    
    /// Test the image with the provided hash.
    ///
    /// A successful test will put the image in a pending state. A pending image will be booted
    /// upon once upon reset, but not again unless confirmed.
    ///
    /// - parameter hash: The hash of the image to test
    /// - parameter callback: The response callback
    public func test(hash: [UInt8], callback: @escaping McuMgrCallback<McuMgrImageStateResponse>) {
        let payload: [String:CBOR] = ["hash": CBOR.byteString(hash),
                                     "confirm": CBOR.boolean(false)]
        send(op: .write, commandId: ID_STATE, payload: payload, callback: callback)
    }
    
    /// Confirm the image with the provided hash.
    ///
    /// A successful confirm will make the image permenant (i.e. the image will be booted upon reset).
    ///
    /// - parameter hash: The hash of the image to test. If not provided, the current image running on the device will
    ///                   be made permenant.
    /// - parameter callback: The response callback
    public func confirm(hash: [UInt8]? = nil, callback: @escaping McuMgrCallback<McuMgrImageStateResponse>) {
        var payload: [String:CBOR] = ["confirm": CBOR.boolean(true)]
        if let hash = hash {
            payload.updateValue(CBOR.byteString(hash), forKey: "hash")
        }
        send(op: .write, commandId: ID_STATE, payload: payload, callback: callback)
    }

    /// Erases an unused image from the secondary image slot on the device.
    ///
    /// The image cannot be erased if the image is a confirmed image, is marked for test on
    /// the next reboot, or is an active image for a split image setup.
    ///
    /// - parameter callback: The response callback
    public func erase(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID_ERASE, payload: nil, callback: callback)
    }

    /// The newtmgr image corelist command lists the core(s) on a device.
    ///
    /// - parameter callback: The response callback
    public func coreList(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .read, commandId: ID_CORELIST, payload: nil, callback: callback)
    }
    
    /// TODO: What does this do?
    public func coreLoad(offset: UInt, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = ["off": CBOR.unsignedInt(offset)]
        send(op: .read, commandId: ID_CORELOAD, payload: payload, callback: callback)
    }

    /// TODO: What does this do?
    public func coreErase(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID_CORELOAD, payload: nil, callback: callback)
    }

    
    //*******************************************************************************************
    // MARK: Image Upload
    //*******************************************************************************************

    /// Image upload states
    public enum UploadState: UInt8 {
        case none = 0
        case uploading = 1
        case paused = 2
    }
    
    public enum ImageUploadError: Error {
        /// Response payload values do not exist
        case invalidPayload
        /// Image Data is nil
        case invalidData
        /// MTU used in the connection is too small
        case insufficientMTU
        /// McuMgrResponse contains a error return code
        case mcuMgrErrorCode(McuMgrReturnCode)
    }
    
    /// State of the image upload
    private var uploadState: UploadState = .none
    /// Address of the target endpoint
    private var uploadAddress = ""
    /// Current image byte offset to send from
    private var offset: UInt = 0
    /// MTU used during upload
    private var mtu: Int {
        if #available(iOS 10.0, *) {
            // For iOS 10.0+
            return 185
        } else {
            // For iOS 9.0
            return 158
        }
    }
    
    /// Contains the image data to send to the device
    private var imageData: Data?
    /// Delegate to send image upload updates to
    private var uploadDelegate: ImageUploadDelegate?

    /// Cancels the current upload.
    ///
    /// If an error is supplied, the delegate's didFailUpload method will be called with the Upload Error provided
    ///
    /// - parameter error: The optional upload error which caused the cancellation. This error (if supplied) is used as
    ///                    the argument for the delegate's didFailUpload method.
    public func cancelUpload(error: Error? = nil) {
        objc_sync_enter(self)
        if error != nil {
            NSLog("UPLOAD LOG: Upload cancelled due to error - \(error!)")
            uploadDelegate?.didFailUpload(bytesSent: Int(offset), imageSize: imageData?.count ?? 0, error: error!)
        }
        print("UPLOAD LOG: Upload cancelled!")
        if uploadState == .none {
            print("There is not an image upload currently in progress.")
        } else {
            resetUploadVariables()
        }
        objc_sync_exit(self)
    }
    
    /// Pauses the current upload. If there is no upload in progress, nothing happens.
    public func pauseUpload() {
        objc_sync_enter(self)
        if uploadState == .none {
            print("UPLOAD LOG: Upload is not in progress and therefore cannot be paused")
        } else {
            print("UPLOAD LOG: Upload paused")
            uploadState = .paused
        }
        objc_sync_exit(self)
    }

    /// Continues a paused upload. If the upload is not paused or not uploading, nothing happens.
    public func continueUpload() {
        objc_sync_enter(self)
        guard let imageData = imageData else {
            if uploadState != .none {
                cancelUpload(error: ImageUploadError.invalidData)
            }
            return
        }
        if uploadState == .paused {
            print("UPLOAD LOG: Continuing upload from \(offset)/\(imageData.count)")
            uploadState = .uploading
            sendUploadData(offset: offset)
        } else {
            print("Upload has not been previously paused");
        }
        objc_sync_exit(self)
    }
    
    /// Begins the image upload to a peripheral.
    ///
    /// An instance of ImageManager can only have one upload in progress at a time. Therefore, if this method is called
    /// multiple times on the same ImageManager instance, all calls after the first will return false. Upload progress
    /// is reported asynchronously to the delegate provided in this method.
    ///
    /// - parameter data: The entire image data in bytes to upload to the peripheral
    /// - parameter peripheral: The BLE periheral to send the data to. The peripneral must be supplied so ImageManager
    ///                         can determine the MTU and thus the number of bytes of image data that it can send per
    ///                         packet.
    /// - parameter delegate: The delegate to recieve progress callbacks.
    ///
    /// - returns: true if the upload has started successfully, false otherwise.
    public func upload(data: [UInt8], delegate: ImageUploadDelegate) -> Bool {
        // Make sure two uploads cant start at once
        objc_sync_enter(self)
        // If upload is already in progress or paused, do not continue
        if uploadState == .none {
            // Set upload flag to true
            uploadState = .uploading
        } else {
            print("UPLOAD LOG: An image upload is already in progress")
            return false
        }
        objc_sync_exit(self)

        // Set upload delegate
        uploadDelegate = delegate
        
        // Set inage data
        imageData = Data(bytes: data)
        
        sendUploadData(offset: 0)
        return true
    }
    
    private func sendUploadData(offset: UInt) {
        // Check if upload is not in progress or paused
        objc_sync_enter(self)
        if uploadState == .none {
            print("UPLOAD LOG: Upload not in progress")
            return
        } else if uploadState == .paused {
            print ("UPLOAD LOG: Image upload has been paused - offset = \(offset)")
            return
        }
        objc_sync_exit(self)
        
        guard let imageData = imageData else {
            cancelUpload(error: ImageUploadError.invalidData)
            return
        }
        
        // Calculate the number of remaining bytes
        let remainingBytes: UInt = UInt(imageData.count) - offset
        
        // Data length to end is the minimum of the max data lenght and the number of remaining bytes
        let packetOverhead = calculatePacketOverhead(data: imageData, offset: offset)
        
        // Get the length of image data to send
        let maxDataLength: UInt = UInt(mtu) - UInt(packetOverhead)
        let dataLength: UInt = min(maxDataLength, remainingBytes)
        NSLog("UPLOAD LOG: offset = \(offset), dataLength = \(dataLength), remainginBytes = \(remainingBytes)")
        
        // Build the request payload
        var payload: [String:CBOR] = ["data": CBOR.byteString([UInt8](imageData[offset..<(offset+dataLength)])),
                                     "off": CBOR.unsignedInt(offset)]
        
        // If this is the initial packet, send the image data length in the payload
        if offset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt(imageData.count)), forKey: "len")
        }
        // Build request and send
        send(op: .write, commandId: ID_UPLOAD, payload: payload, callback: uploadCallback)
    }
    
    private lazy var uploadCallback: McuMgrCallback<McuMgrUploadResponse> = { [unowned self] (response: McuMgrUploadResponse?, error: Error?) in
        // Check for an error
        if let error = error {
            self.cancelUpload(error: error)
            return
        }
        // Make sure the image data is set
        guard let imageData = self.imageData else {
            self.cancelUpload(error: ImageUploadError.invalidData)
            return
        }
        // Make sure the response is not nil
        guard let response = response else {
            self.cancelUpload(error: ImageUploadError.invalidPayload)
            return
        }
        // Check for an error return code
        guard response.isSuccess() else {
            self.cancelUpload(error: ImageUploadError.mcuMgrErrorCode(response.returnCode))
            return
        }
        // Get the offset from the response
        if let offset = response.off {
            // Set the image upload offset
            self.offset = offset
            self.uploadDelegate?.didProgressChange(bytesSent: Int(offset), imageSize: imageData.count, timestamp: Date())
            
            // Check if the upload has completed
            if offset == imageData.count {
                self.uploadDelegate?.didFinishUpload()
                return
            }
            
            // Send the next packet of data
            self.sendUploadData(offset: offset)
        } else {
            self.cancelUpload(error: ImageUploadError.invalidPayload)
            return
        }
    }

    // MARK: - Image Upload Private Methods
    
    private func resetUploadVariables() {
        objc_sync_enter(self)
        // Reset upload state
        uploadState = .none
        
        // Deallocate and nil image data pointers
        imageData = nil
        uploadDelegate = nil
        
        // Reset upload vars
        offset = 0
        uploadAddress = ""
        objc_sync_exit(self)
    }
    
    private func calculatePacketOverhead(data: Data, offset: UInt) -> Int {
        // Get the Newt Manager header
        var payload: [String:CBOR] = ["data": CBOR.byteString([UInt8]([0])),
                                      "off": CBOR.unsignedInt(offset)]
        // If this is the initial packet we have to include the length of the entire image
        if offset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt(data.count)), forKey: "len")
        }
        // Build the packet and return the size
        let packet = buildPacket(op: .write, flags: 0, group: group, sequenceNumber: 0, commandId: ID_UPLOAD, payload: payload)
        var packetOverhead = packet.count + 5
        if transporter.getScheme().isCoap() {
            // Add 25 to the packet size
            packetOverhead = packetOverhead + 25 // add 25 bytes to packet overhead estimate for the CoAP header
        }
        return packetOverhead
    }
}

//******************************************************************
// MARK: Image Upload Delegate
//******************************************************************

public protocol ImageUploadDelegate {
    /// Called when a packet of image data has been sent successfully.
    ///
    /// - parameter bytesSent: The total number of image bytes sent so far
    /// - parameter imageSize: The overall size of the image being uploaded
    /// - parameter timestamp: The time this response packet was received
    func didProgressChange(bytesSent: Int, imageSize: Int, timestamp: Date)

    /// Called when an image upload has failed.
    ///
    /// - parameter bytesSent: The total number of image bytes sent so far
    /// - parameter imageSize: The overall size of the image being uploaded
    /// - parameter error: The error that caused the upload to fail
    func didFailUpload(bytesSent: Int, imageSize: Int, error: Error)

    /// Called when the upload has finished successfully.
    func didFinishUpload()
}

