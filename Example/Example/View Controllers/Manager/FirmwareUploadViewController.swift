/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import McuManager

class FirmwareUploadViewController: UIViewController, McuMgrViewController {
    
    @IBOutlet weak var actionSelect: UIButton!
    @IBOutlet weak var actionStart: UIButton!
    @IBOutlet weak var actionPause: UIButton!
    @IBOutlet weak var actionResume: UIButton!
    @IBOutlet weak var actionCancel: UIButton!
    @IBOutlet weak var status: UILabel!
    @IBOutlet weak var fileHash: UILabel!
    @IBOutlet weak var fileSize: UILabel!
    @IBOutlet weak var fileName: UILabel!
    @IBOutlet weak var progress: UIProgressView!
    
    @IBAction func selectFirmware(_ sender: UIButton) {
        let importMenu = UIDocumentMenuViewController(documentTypes: ["public.data", "public.content"], in: .import)
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = actionSelect
        present(importMenu, animated: true, completion: nil)
    }
    @IBAction func start(_ sender: UIButton) {
        actionStart.isHidden = true
        actionPause.isHidden = false
        actionCancel.isHidden = false
        actionSelect.isEnabled = false
        status.textColor = .primary
        status.text = "UPLOADING..."
        _ = imageManager.upload(data: imageData!, delegate: self)
    }
    @IBAction func pause(_ sender: UIButton) {
        status.textColor = .primary
        status.text = "PAUSED"
        actionPause.isHidden = true
        actionResume.isHidden = false
        imageManager.pauseUpload()
    }
    @IBAction func resume(_ sender: UIButton) {
        status.textColor = .primary
        status.text = "UPLOADING..."
        actionPause.isHidden = false
        actionResume.isHidden = true
        imageManager.continueUpload()
    }
    @IBAction func cancel(_ sender: UIButton) {
        imageManager.cancelUpload()
    }
    
    private var imageData: Data?
    private var imageManager: ImageManager!
    var transporter: McuMgrTransport! {
        didSet {
            imageManager = ImageManager(transporter: transporter)
            imageManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
}

extension FirmwareUploadViewController: ImageUploadDelegate {
    
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        progress.setProgress(Float(bytesSent) / Float(imageSize), animated: true)
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
        imageData = nil
    }
}

// MARK: - Document Picker
extension FirmwareUploadViewController: UIDocumentMenuDelegate, UIDocumentPickerDelegate {
    
    func documentMenu(_ documentMenu: UIDocumentMenuViewController, didPickDocumentPicker documentPicker: UIDocumentPickerViewController) {
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        if let data = dataFrom(url: url) {
            fileName.text = url.lastPathComponent
            fileSize.text = "\(data.count) bytes"
            
            do {
                let hash = try McuMgrImage(data: data).hash
                
                imageData = data
                fileHash.text = hash.hexEncodedString(options: .upperCase)
                status.textColor = .primary
                status.text = "READY"
                actionStart.isEnabled = true
            } catch {
                print("Error reading hash: \(error)")
                fileHash.text = ""
                status.textColor = .systemRed
                status.text = "INVALID FILE"
                actionStart.isEnabled = false
            }
        }
    }
    
    /// Get the image data from the document URL
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
