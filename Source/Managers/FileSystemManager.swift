/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class FileSystemManager: McuManager {
//    
//    //*******************************************************************************************
//    // MARK: File System Constants
//    //*******************************************************************************************
//
//    let FS_NMGR_ID_FILE = UInt8(0)
//    
//    //*******************************************************************************************
//    // MARK: Initializers
//    //*******************************************************************************************
//
//    init(transporter: McuMgrTransport) {
//        super.init(group: .fs, transporter: transporter)
//    }
//    
//    //*******************************************************************************************
//    // MARK: Download
//    //*******************************************************************************************
//
//    /// State of the download
//    private enum DownloadState {
//        case none
//        case downloading
//        case paused
//    }
//    
//    /// The current state of the download
//    private var downloadState: DownloadState = .none
//    /// Download address
//    private var downloadAddress: String = ""
//    /// The src of the file to download
//    private var downloadSrc: String = ""
//    /// Keeps track of the offset while downloading a file
//    private var downloadOffset: UInt = 0
//    /// The downloading file's data
//    private var downloadFileData: Data = Data()
//    /// The expected length of the file. This value is sent in the first response packet.
//    private var downloadFileSize: UInt = 0
//    /// The delegate for this file download
//    private var downloadDelegate: DownloadFileDelegate?
//    
//    /// Reset the necessary varibles for another file download
//    private func resetDownloadVariables() {
//        objc_sync_enter(self)
//        downloadState = .none
//        downloadAddress = ""
//        downloadSrc = ""
//        downloadOffset = 0
//        downloadFileData = Data()
//        downloadDelegate = nil
//    }
//    
//    /// Cancels the current download.
//    ///
//    /// If an error is supplied, the delegate's didFailDownload method will be called with the FileSystemError provided.
//    ///
//    /// - parameter error: The optional upload error which caused the cancellation. This error (if supplied) is used as
//    ///                    the argument for the delegate's didFailDownload method.
//    func cancelDownload(error: FileSystemError? = nil) {
//        objc_sync_enter(self)
//        if error != nil {
//            NSLog("UPLOAD LOG: Upload cancelled due to error - \(error!)")
//            downloadDelegate?.didFailDownload(bytesReceived: Int(downloadOffset), fileSize: Int(downloadFileSize), error: error!)
//        }
//        print("UPLOAD LOG: Upload cancelled!")
//        if downloadState == .none {
//            print("There is not an image upload currently in progress.")
//        } else {
//            resetDownloadVariables()
//        }
//        objc_sync_exit(self)
//    }
//    
//    /// Pauses the current download. If there is no download in progress, nothing happens.
//    func pauseDownload() {
//        objc_sync_enter(self)
//        if downloadState == .none {
//            print("File download is not in progress and therefore cannot be paused")
//        } else {
//            print("File download paused...")
//            downloadState = .paused
//        }
//        objc_sync_exit(self)
//    }
//
//    /// Continues a paused download. If the download is not paused or not in progress, nothing happens.
//    func continueDownload() {
//        objc_sync_enter(self)
//        if downloadState == .paused {
//            print("Continuing file download from \(downloadOffset)/\(downloadFileSize)")
//            downloadState = .downloading
//            sendDownloadRequest()
//        } else {
//            print("Download has not been previously paused");
//        }
//        objc_sync_exit(self)
//    }
//
//    /// Download a file from a device's file system.
//    ///
//    /// - parameter src: The file to download including the path to the file
//    /// - parameter address: The address of the device to download the file from
//    /// - parameter delegate: The delegate to recieve callbacks about the download
//    func download(src: String, address: String, delegate: DownloadFileDelegate) {
//        objc_sync_enter(self)
//        // If download is already in progress or paused, do not continue
//        if downloadState == .none {
//            // Set upload flag to true
//            downloadState = .downloading
//        } else {
//            print("A file download is already in progress")
//            return
//        }
//        objc_sync_exit(self)
//        
//        
//        // Make sure download variables have been reset
//        resetDownloadVariables()
//        
//        // Send the first request
//        sendDownloadRequest()
//    }
//    
//    private func sendDownloadRequest() {
//        // Check if download is not in progress or paused
//        objc_sync_enter(self)
//        if downloadState == .none {
//            return
//        } else if downloadState == .paused {
//            print ("File download has been paused - offset = \(downloadOffset)")
//            return
//        }
//        objc_sync_exit(self)
//        
//        // Build and send the download request
//        let header = McuManager.buildNewtManagerHeader(op: .read, flags: 0, len: 0, group: .fs, seq: 0, id: FS_NMGR_ID_FILE)
//        let values: [String:CBOR] = ["_h": CBOR.byteString(header),
//                                     "name": CBOR.utf8String(downloadSrc),
//                                     "off": CBOR.unsignedInt(downloadOffset)]
//        let request = CoAPRequest(method: .put, uri: McuManager.URI, payload: CBOR.encodeMap(values))
//        CoAPClient.sendCoAPRequest(request, address: downloadAddress, port: McuManager.defaultPort, callback: downloadCallback)
//    }
//    
//    private lazy var downloadCallback: CoAPCallback = { [unowned self] (resource: CoAPResource, response: CoAPResponse) in
//        // Check for CoAP Error
//        if response.code.getStatus() != .success {
//            self.cancelDownload(error: FileSystemError.coapError(response.code))
//            return
//        }
//        
//        // Get the CBOR payload
//        if let cbor = response.payload {
//            // Check for a Newt Manager Error
//            if case let CBOR.unsignedInt(rc)? = cbor["rc"] {
//                let error = NewtManagerError(rawValue: UInt8(rc)) ?? NewtManagerError.unknown
//                if error != .ok {
//                    print ("Newt Manager Error - \(error)")
//                    self.cancelDownload(error: FileSystemError.newtManagerError(error))
//                    return
//                }
//            }
//            // If this is the first response packet, the total file size should be included in the payload
//            if case let CBOR.unsignedInt(len)? = cbor["len"] {
//                self.downloadFileSize = len
//            }
//            
//            // Make sure fileSize has been set, otherwise cancel
//            if self.downloadFileSize == 0 {
//                self.cancelDownload(error: .badPayload)
//            }
//            
//            // Get offset and send next packet
//            if case let CBOR.unsignedInt(off)? = cbor["off"], case let CBOR.byteString(data)? = cbor["data"] {
//                self.downloadOffset = off
//                self.downloadFileData.append(Data(bytes: data))
//                
//                // Call progress delegate function
//                self.downloadDelegate?.didProgressChange(bytesReceived: Int(self.downloadOffset), fileSize: Int(self.downloadFileSize), timestamp: Date())
//                
//                // Check if the download has completed
//                if self.downloadFileData.count >= self.downloadFileSize {
//                    self.downloadDelegate?.didFinishDownload(fileData: self.downloadFileData)
//                    return
//                }
//                
//                // Send the next download request
//                self.sendDownloadRequest()
//            } else {
//                self.cancelDownload(error: FileSystemError.badPayload)
//            }
//        } else {
//            self.cancelDownload(error: FileSystemError.badPayload)
//        }
//    }
//    
//    //*******************************************************************************************
//    // MARK: Upload
//    //*******************************************************************************************
//
//    /// File upload states
//    private enum UploadState: UInt8 {
//        case none = 0
//        case uploading = 1
//        case paused = 2
//    }
//    
//    /// State of the image upload
//    private var uploadState: UploadState = .none
//    /// Address of the target endpoint
//    private var uploadAddress = ""
//    /// The destination to upload to
//    private var uploadFileDestination: String = ""
//    /// Current image byte offset to send from
//    private var uploadOffset: UInt = 0
//    /// MTU used during upload
//    private var uploadMTU: Int = 0
//    
//    /// Contains the image data to send to the device
//    private var uploadFileData: Data?
//    /// Delegate to send image upload updates to
//    private var uploadDelegate: UploadFileDelegate?
//
//    /// Cancels the current upload.
//    ///
//    /// If an error is supplied, the delegate's didFailUpload method will be called with the Upload Error provided
//    ///
//    /// - parameter error: The optional upload error which caused the cancellation. This error (if supplied) is used as the argument for the delegate's didFailUpload method.
//    func cancelUpload(error: FileSystemError? = nil) {
//        objc_sync_enter(self)
//        if error != nil {
//            NSLog("UPLOAD LOG: Upload cancelled due to error - \(error!)")
//            uploadDelegate?.didFailUpload(btyesSent: Int(uploadOffset), imageSize: uploadFileData?.count ?? 0, error: error!)
//        }
//        print("UPLOAD LOG: Upload cancelled!")
//        if uploadState == .none {
//            print("There is not an image upload currently in progress.")
//        } else {
//            resetUploadVariables()
//        }
//        objc_sync_exit(self)
//    }
//
//    /// Pauses the current upload. If there is no upload in progress, nothing happens.
//    func pauseUpload() {
//        objc_sync_enter(self)
//        if uploadState == .none {
//            print("UPLOAD LOG: Upload is not in progress and therefore cannot be paused")
//        } else {
//            print("UPLOAD LOG: Upload paused...")
//            uploadState = .paused
//        }
//        objc_sync_exit(self)
//    }
//    
//    /// Continues a paused upload. If the upload is not paused or not in progress, nothing happens.
//    func continueUpload() {
//        objc_sync_enter(self)
//        guard let imageData = uploadFileData else {
//            cancelUpload(error: .badData)
//            return
//        }
//        if uploadState == .paused {
//            print("UPLOAD LOG: Continuing upload from \(uploadOffset)/\(imageData.count)")
//            uploadState = .uploading
//            sendUploadData(address: uploadAddress, offset: uploadOffset)
//        } else {
//            print("Upload has not been previously paused");
//        }
//        objc_sync_exit(self)
//    }
//    
//    /// Begins the image upload to a peripheral.
//    ///
//    /// An instance of ImageManager can only have one upload in progress at a time. Therefore, if this method is called
//    /// multiple times on the same ImageManager instance, all calls after the first will return false. Upload progress
//    /// is reported asynchronously to the delegate provided in this method.
//    ///
//    /// - parameter data: The entire image data in bytes to upload to the peripheral
//    /// - parameter destination: The device file system destination including the path and file name
//    /// - parameter peripheral: The BLE peripheral to send the data to. The peripheral must be supplied so ImageManager
//    ///                         can determine the MTU and thus the number of bytes of image data that it can send per
//    ///                         packet.
//    /// - parameter delegate: The delegate to receive progress callbacks.
//    ///
//    /// - returns: true if the upload has started successfully, false otherwise.
//    func upload(data: [UInt8], destination: String, peripheral: CBPeripheral, delegate: UploadFileDelegate) -> Bool {
//        // Make sure two uploads cant start at once
//        objc_sync_enter(self)
//        // If upload is already in progress or paused, do not continue
//        if uploadState == .none {
//            // Set upload flag to true
//            uploadState = .uploading
//        } else {
//            print("UPLOAD LOG: An image upload is already in progress")
//            return false
//        }
//        objc_sync_exit(self)
//        
//        // Set upload variables
//        uploadDelegate = delegate
//        uploadAddress = peripheral.identifier.uuidString
//        uploadFileDestination = destination
//        uploadFileData = Data(bytes: data)
//        
//        // Determine the MTU for this image upload
//        var centralMTU: Int = 0
//        if #available(iOS 10.0, *) {
//            // For iOS 10.0+
//            centralMTU = 185
//        } else {
//            // For iOS 9.0
//            centralMTU = 158
//        }
//        let peripheralMTU = peripheral.maximumWriteValueLength(for: CBCharacteristicWriteType.withResponse)
//        uploadMTU = min(centralMTU, peripheralMTU)
//        
//        // Calculate the packet overhead for this packet
//        guard let packetOverhead = calculatePacketOverhead(data: uploadFileData!, offset: 0, destination: uploadFileDestination,isInitialPacket: true) else {
//            cancelUpload(error: .badData)
//            return false
//        }
//        
//        // If the packet overhead is greater than the MTU, cancel the upload with an error
//        if packetOverhead > uploadMTU {
//            cancelUpload(error: .insufficientMTU)
//            return false
//        }
//        
//        // Determine the amount of image data to send
//        let dataLength = uploadMTU - packetOverhead
//        
//        // Get the Newt Manager header
//        let header = McuManager.buildNewtManagerHeader(op: .write, flags: 0, len: 0, group: .fs, seq: 0, id: FS_NMGR_ID_FILE)
//        // Build CBOR payload
//        let rawData: [UInt8] = [UInt8](uploadFileData!)
//        let dataSlice = [UInt8](rawData[0..<dataLength])
//        let values: [String:CBOR] = ["_h": CBOR.byteString(header),
//                                     "data": CBOR.byteString(dataSlice),
//                                     "len": CBOR.unsignedInt(UInt(uploadFileData!.count)),
//                                     "name": CBOR.utf8String(uploadFileDestination),
//                                     "off": CBOR.unsignedInt(0)]
//        // Build request and send
//        let request = CoAPRequest(method: .put, uri: McuManager.URI, payload: CBOR.encodeMap(values))
//        CoAPClient.sendCoAPRequest(request, address: uploadAddress, port: McuManager.defaultPort, callback: uploadCallback)
//        return true
//    }
//    
//    private func sendUploadData(address: String, offset: UInt) {
//        // Check if upload is not in progress or paused
//        objc_sync_enter(self)
//        if uploadState == .none {
//            print("UPLOAD LOG: Upload not in progress")
//            return
//        } else if uploadState == .paused {
//            print ("UPLOAD LOG: Image upload has been paused - offset = \(offset)")
//            return
//        }
//        objc_sync_exit(self)
//        
//        guard let fileData = uploadFileData else {
//            cancelUpload(error: .badData)
//            return
//        }
//        
//        // Check if upload has finished
//        if offset >= fileData.count {
//            print("UPLOAD LOG: Upload Complete!")
//            // Call delegate methods
//            self.uploadDelegate?.didProgressChange(bytesSent: fileData.count, fileSize: fileData.count, timestamp: Date())
//            self.uploadDelegate?.didFinishUpload()
//            
//            // Reset upload variables
//            resetUploadVariables()
//            return
//        }
//        
//        // Calculate the number of remaining bytes
//        let remainingBytes: UInt = UInt(fileData.count) - offset
//        
//        // Data length to end is the minimum of the max data lenght and the number of remaining bytes
//        guard let packetOverhead = calculatePacketOverhead(data: fileData, offset: offset, destination: uploadFileDestination, isInitialPacket: false) else {
//            cancelUpload(error: .badData)
//            return
//        }
//        let maxDataLength: UInt = UInt(uploadMTU) - UInt(packetOverhead)
//        let dataLength: UInt = min(maxDataLength, remainingBytes)
//        NSLog("UPLOAD LOG: offset = \(offset), dataLength = \(dataLength), remainginBytes = \(remainingBytes)")
//        
//        // Get the Newt Manager header
//        let header = McuManager.buildNewtManagerHeader(op: .write, flags: 0, len: 0, group: .fs, seq: 0, id: FS_NMGR_ID_FILE)
//        let values: [String:CBOR] = ["_h": CBOR.byteString(header),
//                                     "data": CBOR.byteString([UInt8](fileData[offset..<(offset+dataLength)])),
//                                     "name": CBOR.utf8String(uploadFileDestination),
//                                     "off": CBOR.unsignedInt(offset)]
//        // Build request and send
//        let request = CoAPRequest(method: .put, uri: McuManager.URI, payload: CBOR.encodeMap(values))
//        CoAPClient.sendCoAPRequest(request, address: uploadAddress, port: McuManager.defaultPort, callback: uploadCallback)
//    }
//    
//    private lazy var uploadCallback: CoAPCallback = { [unowned self] (resource: CoAPResource, response: CoAPResponse) in
//        // Check for CoAP Error
//        if response.code.getStatus() != .success {
//            self.cancelUpload(error: .coapError(response.code))
//            return
//        }
//        if let cbor = response.payload {
//            // Check for a Newt Manager Error
//            if case let CBOR.unsignedInt(rc)? = cbor["rc"] {
//                let error = NewtManagerError(rawValue: UInt8(rc)) ?? NewtManagerError.unknown
//                if error != .ok {
//                    print ("UPLOAD LOG: NMGR ERROR - \(error)")
//                    self.cancelUpload(error: .newtManagerError(error))
//                    return
//                }
//            }
//            // Get offset and send next packet
//            if case let CBOR.unsignedInt(off)? = cbor["off"] {
//                self.uploadOffset = off
//                if let fileData = self.uploadFileData {
//                    self.uploadDelegate?.didProgressChange(bytesSent: Int(self.uploadOffset), fileSize: fileData.count, timestamp: Date())
//                    self.sendUploadData(address: self.uploadAddress, offset: self.uploadOffset)
//                }
//            } else {
//                self.cancelUpload(error: .badPayload)
//            }
//        } else {
//            self.cancelUpload(error: .badPayload)
//        }
//    }
//    
//    // MARK: Image Upload Private Methods
//    
//    private func resetUploadVariables() {
//        objc_sync_enter(self)
//        // Reset upload state
//        uploadState = .none
//        
//        // Deallocate and nil image data pointers
//        uploadFileData = nil
//        uploadDelegate = nil
//        
//        // Reset upload vars
//        uploadMTU = 0
//        uploadOffset = 0
//        uploadAddress = ""
//        uploadFileDestination = ""
//        objc_sync_exit(self)
//    }
//    
//    private func calculatePacketOverhead(data: Data, offset: UInt, destination: String, isInitialPacket: Bool) -> Int? {
//        // Get the Newt Manager header
//        let header = McuManager.buildNewtManagerHeader(op: .write, flags: 0, len: 0, group: .fs, seq: 0, id: FS_NMGR_ID_FILE)
//        var values: [String:CBOR] = ["_h": CBOR.byteString(header),
//                                     "data": CBOR.byteString([UInt8]([0])),
//                                     "name": CBOR.utf8String(destination),
//                                     "off": CBOR.unsignedInt(offset)]
//        // If this is the initial packet we have to include the length of the entire image
//        if isInitialPacket {
//            values.updateValue(CBOR.unsignedInt(UInt(data.count)), forKey: "len")
//        }
//        // Build a CoAPRequest
//        let request = CoAPRequest(method: .put, uri: McuManager.URI, payload: CBOR.encodeMap(values))
//        // Calculate length of packet data
//        guard let overhead = request.scMessage.toData()?.count else {
//            return nil
//        }
//        return overhead
//    }
}

//*******************************************************************************************
// MARK: - Download/Upload Delegates
//*******************************************************************************************

///// Callbacks which are called when downloading a file from a peripheral.
//protocol DownloadFileDelegate {
//    /// Called when a new packet of file data has been received.
//    ///
//    /// - parameter bytesReceived: The total number of bytes received so far
//    /// - parameter fileSize: The overall file size of the file being downloaded in bytes
//    /// - parameter timestamp: The time this packet was received
//    func didProgressChange(bytesReceived: Int, fileSize: Int, timestamp: Date)
//
//    /// Called when the download has failed.
//    ///
//    /// - parameter bytesReceived: The total number of bytes received before the error
//    /// - parameter fileSize: The size of the file in bytes
//    /// - parameter error: The error which caused the file download to fail
//    func didFailDownload(bytesReceived: Int, fileSize: Int, error: FileSystemError)
//
//    /// Called when the download has finished successfully.
//    ///
//    /// - parameter fileData: The data of the downloaded file
//    func didFinishDownload(fileData: Data)
//}
//
///// Callbacks which are called when uploading a file to a peripheral.
//protocol UploadFileDelegate {
//    /// Called when a packet of file data has been sent successfully.
//    ///
//    /// - parameter bytesSent: The total number of bytes sent so far
//    /// - parameter fileSize: The overall file size of the file being uploaded in bytes
//    /// - parameter timestamp: The time the successful packet response was received
//    func didProgressChange(bytesSent: Int, fileSize: Int, timestamp: Date)
//
//    /// Called when the file upload has failed.
//    ///
//    /// - parameter bytesSent: The total number of bytes sent before the error
//    /// - parameter fileSize: The size of the file in bytes
//    /// - parameter error: The error which caused the file upload to fail
//    func didFailUpload(btyesSent: Int, imageSize: Int, error: FileSystemError)
//
//    /// Called when the upload has finished successfully.
//    func didFinishUpload()
//}
//
///// Errors that occur during file system download/upload fall into one of three classes:
/////    * CoAP
/////    * Newt Manager
/////    * Upload
/////
///// **CoAP Error:**
///// A CoAP error occurs when the CoAP response contains an error code. These errors can occur in our CoAP Client or come
///// from the CoAP Server. See CoAPResponseCode for more detail.
/////
///// **Newt Manager Error:**
///// A Newt Manager error is sent back from the end device and represents and error that has occured on the device. For
///// example the device could run out of memory or a packet may have been lost of have a bad format; all of which would
///// trigger a Newt Manager error response. See NewtManagerError for all the codes.
/////
///// **File System Error:**
///// File System errors are rare and occur from within FileSystemManager. See the error cases within this enum for more
///// details.
//enum FileSystemError: Error {
//
//    /// MARK: Internal ImageManager Errors
//
//    /// Response payload values do not exist
//    case badPayload
//    /// Image Data is nil
//    case badData
//    /// MTU used in the connection is too small
//    case insufficientMTU
//    /// Newt Manager Error Code
//    case newtManagerError(McuMgrReturnCode)
//}
