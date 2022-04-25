/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import McuManager

// MARK: - FirmwareUploadViewController

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
        guard let package = package else { return }
        
        guard package.images.count > 1 else {
            actionStart.isHidden = true
            actionPause.isHidden = false
            actionCancel.isHidden = false
            actionSelect.isEnabled = false
            imageSlot = 0
            status.textColor = .primary
            status.text = "UPLOADING..."
            _ = imageManager.upload(images: [ImageManager.Image(image: 0, data: package.images[0].data)], delegate: self)
            return
        }
        
        let alertController = UIAlertController(title: "Select Core Slot", message: nil, preferredStyle: .actionSheet)
        for image in package.images {
            alertController.addAction(UIAlertAction(title: McuMgrPackage.imageName(at: image.image), style: .default) { [weak self]
                action in
                self?.actionStart.isHidden = true
                self?.actionPause.isHidden = false
                self?.actionCancel.isHidden = false
                self?.actionSelect.isEnabled = false
                self?.imageSlot = image.image
                self?.status.textColor = .primary
                self?.status.text = "UPLOADING \(McuMgrPackage.imageName(at: image.image))..."
                _ = self?.imageManager.upload(images: [ImageManager.Image(image: image.image, data: image.data)], delegate: self)
            })
        }
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    
        // If the device is an iPad set the popover presentation controller
        if let presenter = alertController.popoverPresentationController {
            presenter.sourceView = self.view
            presenter.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            presenter.permittedArrowDirections = []
        }
        present(alertController, animated: true)
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
        if let image = self.imageSlot {
            status.text = "UPLOADING IMAGE \(McuMgrPackage.imageName(at: image))..."
        } else {
            status.text = "UPLOADING..."
        }
        actionPause.isHidden = false
        actionResume.isHidden = true
        imageManager.continueUpload()
    }
    @IBAction func cancel(_ sender: UIButton) {
        imageManager.cancelUpload()
    }
    
    private var imageSlot: Int?
    private var package: McuMgrPackage?
    private var imageManager: ImageManager!
    var transporter: McuMgrTransport! {
        didSet {
            imageManager = ImageManager(transporter: transporter)
            imageManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
}

// MARK: - ImageUploadDelegate

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
        package = nil
    }
}

// MARK: - Document Picker

extension FirmwareUploadViewController: UIDocumentMenuDelegate, UIDocumentPickerDelegate {
    
    func documentMenu(_ documentMenu: UIDocumentMenuViewController, didPickDocumentPicker documentPicker: UIDocumentPickerViewController) {
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        do {
            let package = try McuMgrPackage(from: url)
            self.package = package
            fileName.text = url.lastPathComponent
            fileSize.text = package.sizeString()
            fileSize.numberOfLines = 0
            fileHash.text = try package.hashString()
            fileHash.numberOfLines = 0
            
            status.textColor = .primary
            status.text = "READY"
            actionStart.isEnabled = true
        } catch {
            print("Error reading hash: \(error)")
            fileSize.text = ""
            fileHash.text = ""
            status.textColor = .systemRed
            status.text = "INVALID FILE"
            actionStart.isEnabled = false
        }
    }
}
