/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary
import UniformTypeIdentifiers

// MARK: - FileUploadViewController

class FileUploadViewController: UIViewController, McuMgrViewController {

    // MARK: @IBOutlet(s)
    
    @IBOutlet weak var fileName: UILabel!
    @IBOutlet weak var fileSize: UILabel!
    @IBOutlet weak var destination: UILabel!
    @IBOutlet weak var status: UILabel!
    @IBOutlet weak var progress: UIProgressView!
    
    @IBOutlet weak var actionSelect: UIButton!
    @IBOutlet weak var actionStart: UIButton!
    @IBOutlet weak var actionPause: UIButton!
    @IBOutlet weak var actionResume: UIButton!
    @IBOutlet weak var actionCancel: UIButton!
    
    // MARK: @IBAction(s)
    
    @IBAction func selectFile(_ sender: UIButton) {
        let supportedDocumentTypes = ["public.data", "public.content"]
        let importMenu = UIDocumentPickerViewController(documentTypes: supportedDocumentTypes,
                                                        in: .import)
        importMenu.allowsMultipleSelection = false
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = actionSelect
        present(importMenu, animated: true, completion: nil)
    }
    
    @IBAction func start(_ sender: UIButton) {
        guard let destination = destination.text, let fileData,
              let filesViewController = parent as? FilesController,
              let baseController = filesViewController.parent as? BaseViewController else { return }
        
        actionStart.isHidden = true
        actionPause.isHidden = false
        actionCancel.isHidden = false
        actionSelect.isEnabled = false
        status.textColor = .primary
        status.text = "UPLOADING..."
        
        if let downloadViewController = filesViewController.fileDownloadViewController {
            downloadViewController.addRecent(fileName.text!)
        }
        baseController.onDeviceStatusReady { [unowned self] in
            _ = fsManager.upload(name: destination, data: fileData,
                                 delegate: self)
        }
    }
    
    @IBAction func pause(_ sender: UIButton) {
        status.textColor = .primary
        status.text = "PAUSED"
        actionPause.isHidden = true
        actionResume.isHidden = false
        fsManager.pauseTransfer()
    }
    
    @IBAction func resume(_ sender: UIButton) {
        status.textColor = .primary
        status.text = "UPLOADING..."
        actionPause.isHidden = false
        actionResume.isHidden = true
        fsManager.continueTransfer()
    }
    
    @IBAction func cancel(_ sender: UIButton) {
        fsManager.cancelTransfer()
    }
    
    var transport: McuMgrTransport! {
        didSet {
            fsManager = FileSystemManager(transport: transport)
            fsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    
    // MARK: Private Properties
    
    private var fsManager: FileSystemManager!
    private var fileData: Data?
    private var partition: String {
        return UserDefaults.standard
            .string(forKey: FilesController.partitionKey)
            ?? FilesController.defaultPartition
    }
    
    private var uploadTimestamp: Date!
    private var uploadImageSize: Int!
    private var initialBytes: Int!
    
    private func refreshDestination() {
        if let _ = fileData {
            destination.text = "/\(partition)/\(fileName.text!)"
        }
    }
    
    // MARK: UIViewController API
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.translatesAutoresizingMaskIntoConstraints = false
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshDestination()
    }
}

// MARK: - FileUploadDelegate

extension FileUploadViewController: FileUploadDelegate {
    
    func uploadProgressDidChange(bytesSent: Int, fileSize: Int, timestamp: Date) {
        if uploadImageSize == nil || uploadImageSize != fileSize {
            uploadTimestamp = timestamp
            uploadImageSize = fileSize
            initialBytes = bytesSent
        }
        
        // Date.timeIntervalSince1970 returns seconds
        let msSinceUploadBegan = max((timestamp.timeIntervalSince1970 - uploadTimestamp.timeIntervalSince1970) * 1000, 1)
        let speedInKiloBytesPerSecond: Double
        if bytesSent < fileSize {
            let bytesSentSinceUploadBegan = bytesSent - initialBytes
            // bytes / ms = kB/s
            speedInKiloBytesPerSecond = Double(bytesSentSinceUploadBegan) / msSinceUploadBegan
        } else {
            // bytes / ms = kB/s
            speedInKiloBytesPerSecond = Double(fileSize - initialBytes) / msSinceUploadBegan
        }
        
        status.text = "UPLOADING... (\(String(format: "%.2f", speedInKiloBytesPerSecond)) kB/s)"
        progress.setProgress(Float(bytesSent) / Float(fileSize), animated: true)
    }
    
    func uploadDidFail(with error: Error) {
        progress.setProgress(0, animated: true)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionStart.isHidden = false
        actionSelect.isEnabled = true
        status.textColor = .systemRed
        status.text = error.localizedDescription
    }
    
    func uploadDidCancel() {
        progress.setProgress(0, animated: true)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionStart.isHidden = false
        actionSelect.isEnabled = true
        status.textColor = .secondary
        status.text = "CANCELLED"
    }
    
    func uploadDidFinish() {
        progress.setProgress(0, animated: false)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionStart.isHidden = false
        actionStart.isEnabled = false
        actionSelect.isEnabled = true
        status.textColor = .secondary
        status.text = "UPLOAD COMPLETE"
        fileData = nil
    }
}

// MARK: - UIDocumentPickerDelegate

extension FileUploadViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentAt url: URL) {
        if let data = dataFrom(url: url) {
            self.fileData = data
            
            fileName.text = url.lastPathComponent
            fileSize.text = "\(data.count) bytes"
            refreshDestination()
            
            status.textColor = .secondary
            status.text = "READY"
            actionStart.isEnabled = true
        }
    }
    
    /// Get the file data from the document URL
    private func dataFrom(url: URL) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            status.textColor = .systemRed
            status.text = error.localizedDescription
            return nil
        }
    }
}
