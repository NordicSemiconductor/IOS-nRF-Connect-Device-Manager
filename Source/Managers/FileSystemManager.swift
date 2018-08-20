/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class FileSystemManager: McuManager {
    private static let TAG = "FileSystemManager"
    
    //**************************************************************************
    // MARK: FS Constants
    //**************************************************************************
    
    // Mcu File System Manager ids
    let ID_FILE        =  UInt8(0)
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************
    
    public init(transporter: McuMgrTransport) {
        super.init(group: .fs, transporter: transporter)
    }
    
    //**************************************************************************
    // MARK: File System Commands
    //**************************************************************************
    
    /// Requests the next packet of data from given offset.
    /// To download a complete file, use download(name:delegate) method instead.
    ///
    /// - parameter name: The file name.
    /// - parameter offset: The offset from this data will be requested.
    /// - parameter callback: The callback.
    public func download(name: String, offset: UInt, callback: @escaping McuMgrCallback<McuMgrFsDownloadResponse>) {
        // Build the request payload.
        let payload: [String:CBOR] = ["name": CBOR.utf8String(name),
                                      "off": CBOR.unsignedInt(offset)]
        // Build request and send.
        send(op: .read, commandId: ID_FILE, payload: payload, callback: callback)
    }

    /// Sends the next packet of data from given offset.
    /// To send a complete file, use upload(name:data:delegate) method instead.
    ///
    /// - parameter name: The file name.
    /// - parameter data: The file data.
    /// - parameter offset: The offset from this data will be sent.
    /// - parameter callback: The callback.
    public func upload(name: String, data: Data, offset: UInt, callback: @escaping McuMgrCallback<McuMgrFsUploadResponse>) {
        // Calculate the number of remaining bytes.
        let remainingBytes: UInt = UInt(data.count) - offset
        
        // Data length to end is the minimum of the max data lenght and the
        // number of remaining bytes.
        let packetOverhead = calculatePacketOverhead(name: name, data: data, offset: offset)
        
        // Get the length of file data to send.
        let maxDataLength: UInt = UInt(mtu) - UInt(packetOverhead)
        let dataLength: UInt = min(maxDataLength, remainingBytes)
        
        // Build the request payload.
        var payload: [String:CBOR] = ["name": CBOR.utf8String(name),
                                      "data": CBOR.byteString([UInt8](data[offset..<(offset+dataLength)])),
                                      "off": CBOR.unsignedInt(offset)]
        
        // If this is the initial packet, send the file data length.
        if offset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt(data.count)), forKey: "len")
        }
        // Build request and send.
        send(op: .write, commandId: ID_FILE, payload: payload, callback: callback)
    }
    
    /// Begins the file download from a peripheral.
    ///
    /// An instance of FileSystemManager can only have one transfer in progress
    /// at a time. Therefore, if this method is called multiple times on the same
    /// FileSystemManager instance, all calls after the first will return false.
    /// Download progress is reported asynchronously to the delegate provided in
    /// this method.
    ///
    /// - parameter name: The file name to download.
    /// - parameter peripheral: The BLE periheral to get the data form.
    /// - parameter delegate: The delegate to recieve progress callbacks.
    ///
    /// - returns: True if the upload has started successfully, false otherwise.
    public func download(name: String, delegate: FileDownloadDelegate) -> Bool {
        // Make sure two uploads cant start at once.
        objc_sync_enter(self)
        // If upload is already in progress or paused, do not continue.
        if transferState == .none {
            // Set downloading flag to true.
            transferState = .downloading
        } else {
            Log.d(FileSystemManager.TAG, msg: "A file transfer is already in progress")
            return false
        }
        objc_sync_exit(self)
        
        // Set upload delegate.
        downloadDelegate = delegate
        
        // Set file data.
        fileName = name
        fileData = nil
        
        download(name: name, offset: 0, callback: downloadCallback)
        return true
    }
    
    /// Begins the file upload to a peripheral.
    ///
    /// An instance of FileSystemManager can only have one upload in progress at a
    /// time. Therefore, if this method is called multiple times on the same
    /// FileSystemManager instance, all calls after the first will return false.
    /// Upload progress is reported asynchronously to the delegate provided in
    /// this method.
    ///
    /// - parameter name: The file name.
    /// - parameter data: The file data to be sent to the peripheral.
    /// - parameter peripheral: The BLE periheral to send the data to. The
    ///   peripneral must be supplied so FileSystemManager can determine the MTU and
    ///   thus the number of bytes of file data that it can send per packet.
    /// - parameter delegate: The delegate to recieve progress callbacks.
    ///
    /// - returns: True if the upload has started successfully, false otherwise.
    public func upload(name: String, data: Data, delegate: FileUploadDelegate) -> Bool {
        // Make sure two uploads cant start at once.
        objc_sync_enter(self)
        // If upload is already in progress or paused, do not continue.
        if transferState == .none {
            // Set upload flag to true.
            transferState = .uploading
        } else {
            Log.d(FileSystemManager.TAG, msg: "A file transfer is already in progress")
            return false
        }
        objc_sync_exit(self)
        
        // Set upload delegate.
        uploadDelegate = delegate
        
        // Set file data.
        fileName = name
        fileData = data
        
        upload(name: name, data: fileData!, offset: 0, callback: uploadCallback)
        return true
    }
    
    //**************************************************************************
    // MARK: Image Upload
    //**************************************************************************
    
    /// Image upload states
    public enum UploadState: UInt8 {
        case none = 0
        case uploading = 1
        case downloading = 2
        case paused = 3
    }
    
    /// State of the file upload.
    private var transferState: UploadState = .none
    /// Current file byte offset to send from.
    private var offset: UInt = 0
    
    /// The file name.
    private var fileName: String?
    /// Contains the file data to send to the device.
    private var fileData: Data?
    /// Delegate to send file upload updates to.
    private var uploadDelegate: FileUploadDelegate?
    /// Delegate to send file download updates to.
    private var downloadDelegate: FileDownloadDelegate?
    
    /// Cancels the current transfer.
    ///
    /// If an error is supplied, the delegate's didFailUpload method will be
    /// called with the Upload Error provided.
    ///
    /// - parameter error: The optional upload error which caused the
    ///   cancellation. This error (if supplied) is used as the argument for the
    ///   delegate's didFailUpload/Download method.
    public func cancelTransfer(error: Error? = nil) {
        objc_sync_enter(self)
        if transferState == .none {
            Log.d(FileSystemManager.TAG, msg: "Transfer is not in progress")
        } else {
            if error != nil {
                Log.d(FileSystemManager.TAG, msg: "Transfer cancelled due to error: \(error!)")
                resetTransfer()
                uploadDelegate?.uploadDidFail(with: error!)
                uploadDelegate = nil
                downloadDelegate?.downloadDidFail(with: error!)
                downloadDelegate = nil
            } else {
                if transferState == .paused {
                    Log.d(FileSystemManager.TAG, msg: "Transfer cancelled!")
                    resetTransfer()
                    uploadDelegate?.uploadDidCancel()
                    downloadDelegate?.downloadDidCancel()
                    uploadDelegate = nil
                    downloadDelegate = nil
                }
                // else
                // Transfer will be cancelled after the next notification is received.
            }
            transferState = .none
        }
        objc_sync_exit(self)
    }
    
    /// Pauses the current transfer. If there is no transfer in progress, nothing
    /// happens.
    public func pauseTransfer() {
        objc_sync_enter(self)
        if transferState == .none {
            Log.d(FileSystemManager.TAG, msg: "Transfer is not in progress and therefore cannot be paused")
        } else {
            Log.d(FileSystemManager.TAG, msg: "Transfer paused")
            transferState = .paused
        }
        objc_sync_exit(self)
    }
    
    /// Continues a paused transfer. If the transfer is not paused or not uploading,
    /// nothing happens.
    public func continueTransfer() {
        objc_sync_enter(self)
        if transferState == .paused {
            Log.d(FileSystemManager.TAG, msg: "Continuing transfer")
            if let _ = downloadDelegate {
                transferState = .downloading
                download(name: fileName!, offset: offset, callback: downloadCallback)
            } else {
                transferState = .uploading
                upload(name: fileName!, data: fileData!, offset: offset, callback: uploadCallback)
            }
        } else {
            Log.d(FileSystemManager.TAG, msg: "Transfer is not paused")
        }
        objc_sync_exit(self)
    }
    
    //**************************************************************************
    // MARK: File Transfer Private Methods
    //**************************************************************************
    
    private lazy var uploadCallback: McuMgrCallback<McuMgrFsUploadResponse> = {
        [unowned self] (response: McuMgrFsUploadResponse?, error: Error?) in
        // Check for an error.
        if let error = error {
            if case let McuMgrTransportError.insufficientMtu(newMtu) = error {
                if !self.setMtu(newMtu) {
                    self.cancelTransfer(error: error)
                } else {
                    self.restartTransfer()
                }
                return
            }
            self.cancelTransfer(error: error)
            return
        }
        // Make sure the file data is set.
        guard let fileData = self.fileData else {
            self.cancelTransfer(error: FileTransferError.invalidData)
            return
        }
        // Make sure the response is not nil.
        guard let response = response else {
            self.cancelTransfer(error: FileTransferError.invalidPayload)
            return
        }
        // Check for an error return code.
        guard response.isSuccess() else {
            self.cancelTransfer(error: FileTransferError.mcuMgrErrorCode(response.returnCode))
            return
        }
        // Get the offset from the response.
        if let offset = response.off {
            // Set the file upload offset.
            self.offset = offset
            self.uploadDelegate?.uploadProgressDidChange(bytesSent: Int(offset), fileSize: fileData.count, timestamp: Date())
            
            if self.transferState == .none {
                Log.d(FileSystemManager.TAG, msg: "Upload cancelled!")
                self.resetTransfer()
                self.uploadDelegate?.uploadDidCancel()
                self.uploadDelegate = nil
                return
            }
            
            // Check if the upload has completed.
            if offset == fileData.count {
                Log.d(FileSystemManager.TAG, msg: "Upload finished!")
                self.resetTransfer()
                self.uploadDelegate?.uploadDidFinish()
                self.uploadDelegate = nil
                return
            }
            
            // Send the next packet of data.
            self.sendNext(from: offset)
        } else {
            self.cancelTransfer(error: ImageUploadError.invalidPayload)
        }
    }
    
    private lazy var downloadCallback: McuMgrCallback<McuMgrFsDownloadResponse> = {
        [unowned self] (response: McuMgrFsDownloadResponse?, error: Error?) in
        // Check for an error.
        if let error = error {
            if case let McuMgrTransportError.insufficientMtu(newMtu) = error {
                if !self.setMtu(newMtu) {
                    self.cancelTransfer(error: error)
                } else {
                    self.restartTransfer()
                }
                return
            }
            self.cancelTransfer(error: error)
            return
        }
        // Make sure the response is not nil.
        guard let response = response else {
            self.cancelTransfer(error: FileTransferError.invalidPayload)
            return
        }
        // Check for an error return code.
        guard response.isSuccess() else {
            self.cancelTransfer(error: FileTransferError.mcuMgrErrorCode(response.returnCode))
            return
        }
        // Get the offset from the response.
        if let offset = response.off, let data = response.data {
            // The first packet contains the file length.
            if offset == 0 {
                if let len = response.len {
                    self.fileData = Data(capacity: Int(len))
                } else {
                    self.cancelTransfer(error: FileTransferError.invalidPayload)
                }
            }
            // Set the file upload offset.
            self.offset = offset + UInt(data.count)
            self.fileData!.append(contentsOf: data)
            self.downloadDelegate?.downloadProgressDidChange(bytesDownloaded: Int(self.offset), fileSize: self.fileData!.count, timestamp: Date())
            
            if self.transferState == .none {
                Log.d(FileSystemManager.TAG, msg: "Download cancelled!")
                self.resetTransfer()
                self.downloadDelegate?.downloadDidCancel()
                self.downloadDelegate = nil
                return
            }
            
            // Check if the upload has completed.
            if self.offset == self.fileData!.count {
                Log.d(FileSystemManager.TAG, msg: "Download finished!")
                self.transferState = .none
                self.downloadDelegate?.download(of: self.fileName!, didFinish: self.fileData!)
                self.downloadDelegate = nil
                self.resetTransfer()
                return
            }
            
            // Send the next packet of data.
            self.requestNext(from: offset)
        } else {
            self.cancelTransfer(error: FileTransferError.invalidPayload)
        }
    }
    
    private func sendNext(from offset: UInt) {
        if transferState != .uploading {
            return
        }
        upload(name: fileName!, data: fileData!, offset: offset, callback: uploadCallback)
    }
    
    private func requestNext(from offset: UInt) {
        if transferState != .downloading {
            return
        }
        download(name: fileName!, offset: offset, callback: downloadCallback)
    }
    
    private func resetTransfer() {
        objc_sync_enter(self)
        // Reset upload state.
        transferState = .none
        
        // Deallocate and nil file data pointers.
        fileData = nil
        fileName = nil
        
        // Reset upload vars.
        offset = 0
        objc_sync_exit(self)
    }
    
    private func restartTransfer() {
        objc_sync_enter(self)
        transferState = .none
        if let uploadDelegate = uploadDelegate {
            _ = upload(name: fileName!, data: fileData!, delegate: uploadDelegate)
        } else if let downloadDelegate = downloadDelegate {
            _ = download(name: fileName!, delegate: downloadDelegate)
        }
        objc_sync_exit(self)
    }
    
    private func calculatePacketOverhead(name: String, data: Data, offset: UInt) -> Int {
        // Get the Mcu Manager header.
        var payload: [String:CBOR] = ["name": CBOR.utf8String(name),
                                      "data": CBOR.byteString([UInt8]([0])),
                                      "off": CBOR.unsignedInt(offset)]
        // If this is the initial packet we have to include the length of the
        // entire file.
        if offset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt(data.count)), forKey: "len")
        }
        // Build the packet and return the size.
        let packet = buildPacket(op: .write, flags: 0, group: group, sequenceNumber: 0, commandId: ID_FILE, payload: payload)
        var packetOverhead = packet.count + 5
        if transporter.getScheme().isCoap() {
            // Add 25 bytes to packet overhead estimate for the CoAP header.
            packetOverhead = packetOverhead + 25
        }
        return packetOverhead
    }
}

public enum FileTransferError: Error {
    /// Response payload values do not exist.
    case invalidPayload
    /// File Data is nil.
    case invalidData
    /// McuMgrResponse contains a error return code.
    case mcuMgrErrorCode(McuMgrReturnCode)
}

extension FileTransferError: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .invalidPayload:
            return "Response payload values do not exist."
        case .invalidData:
            return "File data is nil."
        case .mcuMgrErrorCode(let code):
            return "\(code)"
        }
    }
}

//******************************************************************************
// MARK: File Upload Delegate
//******************************************************************************

public protocol FileUploadDelegate {
    
    /// Called when a packet of file data has been sent successfully.
    ///
    /// - parameter bytesSent: The total number of file bytes sent so far.
    /// - parameter fileSize:  The overall size of the file being uploaded.
    /// - parameter timestamp: The time this response packet was received.
    func uploadProgressDidChange(bytesSent: Int, fileSize: Int, timestamp: Date)
    
    /// Called when an file upload has failed.
    ///
    /// - parameter error: The error that caused the upload to fail.
    func uploadDidFail(with error: Error)
    
    /// Called when the upload has been cancelled.
    func uploadDidCancel()
    
    /// Called when the upload has finished successfully.
    func uploadDidFinish()
}

//******************************************************************************
// MARK: File Download Delegate
//******************************************************************************

public protocol FileDownloadDelegate {
    
    /// Called when a packet of file data has been sent successfully.
    ///
    /// - parameter bytesDownloaded: The total number of file bytes received so far.
    /// - parameter fileSize:        The overall size of the file being downloaded.
    /// - parameter timestamp:       The time this response packet was received.
    func downloadProgressDidChange(bytesDownloaded: Int, fileSize: Int, timestamp: Date)
    
    /// Called when an file download has failed.
    ///
    /// - parameter error: The error that caused the download to fail.
    func downloadDidFail(with error: Error)
    
    /// Called when the download has been cancelled.
    func downloadDidCancel()
    
    /// Called when the download has finished successfully.
    ///
    /// - parameter name: The file name.
    /// - parameter data: The file content.
    func download(of name: String, didFinish data: Data)
}
