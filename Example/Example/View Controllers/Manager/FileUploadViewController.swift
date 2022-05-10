/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class FileUploadViewController: UIViewController, McuMgrViewController {

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
    
    @IBAction func selectFile(_ sender: UIButton) {
        let importMenu = UIDocumentMenuViewController(documentTypes: ["public.data", "public.content"], in: .import)
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = actionSelect
        present(importMenu, animated: true, completion: nil)
    }
    @IBAction func start(_ sender: UIButton) {
        let downloadViewController = (parent as? FilesController)?.fileDownloadViewController
        downloadViewController?.addRecent(fileName.text!)
        
        actionStart.isHidden = true
        actionPause.isHidden = false
        actionCancel.isHidden = false
        actionSelect.isEnabled = false
        status.textColor = .primary
        status.text = "UPLOADING..."
        _ = fsManager.upload(name: destination.text!, data: fileData!, delegate: self)
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
    
    var transporter: McuMgrTransport! {
        didSet {
            fsManager = FileSystemManager(transporter: transporter)
            fsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    
    private var fsManager: FileSystemManager!
    private var fileData: Data?
    private var partition: String {
        return UserDefaults.standard
            .string(forKey: FilesController.partitionKey)
            ?? FilesController.defaultPartition
    }
    
    private func refreshDestination() {
        if let _ = fileData {
            destination.text = "/\(partition)/\(fileName.text!)"
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        refreshDestination()
    }
}

extension FileUploadViewController: FileUploadDelegate {
    
    func uploadProgressDidChange(bytesSent: Int, fileSize: Int, timestamp: Date) {
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
        status.text = "\(error.localizedDescription)"
    }
    
    func uploadDidCancel() {
        progress.setProgress(0, animated: true)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionStart.isHidden = false
        actionSelect.isEnabled = true
        status.textColor = .primary
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
        status.textColor = .primary
        status.text = "UPLOAD COMPLETE"
        fileData = nil
    }
}

// MARK: - Document Picker
extension FileUploadViewController: UIDocumentMenuDelegate, UIDocumentPickerDelegate {
    
    func documentMenu(_ documentMenu: UIDocumentMenuViewController,
                      didPickDocumentPicker documentPicker: UIDocumentPickerViewController) {
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentAt url: URL) {
        if let data = dataFrom(url: url) {
            self.fileData = data
            
            fileName.text = url.lastPathComponent
            fileSize.text = "\(data.count) bytes"
            refreshDestination()
            
            status.textColor = .primary
            status.text = "READY"
            actionStart.isEnabled = true
        }
    }
    
    /// Get the file data from the document URL
    private func dataFrom(url: URL) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            print("Error reading file: \(error)")
            status.textColor = .systemRed
            status.text = "COULD NOT OPEN FILE"
            return nil
        }
    }
}
