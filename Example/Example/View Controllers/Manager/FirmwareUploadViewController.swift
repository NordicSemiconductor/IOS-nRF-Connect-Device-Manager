/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

// MARK: - FirmwareUploadViewController

class FirmwareUploadViewController: UIViewController, McuMgrViewController {
    
    @IBOutlet weak var actionBuffers: UIButton!
    @IBOutlet weak var actionAlignment: UIButton!
    @IBOutlet weak var actionChunks: UIButton!
    @IBOutlet weak var actionSelect: UIButton!
    @IBOutlet weak var actionStart: UIButton!
    @IBOutlet weak var actionPause: UIButton!
    @IBOutlet weak var actionResume: UIButton!
    @IBOutlet weak var actionCancel: UIButton!
    @IBOutlet weak var status: UILabel!
    @IBOutlet weak var fileHash: UILabel!
    @IBOutlet weak var fileSize: UILabel!
    @IBOutlet weak var fileName: UILabel!
    @IBOutlet weak var dfuNumberOfBuffers: UILabel!
    @IBOutlet weak var dfuByteAlignment: UILabel!
    @IBOutlet weak var dfuChunkSize: UILabel!
    @IBOutlet weak var dfuSpeed: UILabel!
    @IBOutlet weak var progress: UIProgressView!
    
    @IBAction func selectFirmware(_ sender: UIButton) {
        let supportedDocumentTypes = ["com.apple.macbinary-archive", "public.zip-archive", "com.pkware.zip-archive"]
        let importMenu = UIDocumentMenuViewController(documentTypes: supportedDocumentTypes,
                                                      in: .import)
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = actionSelect
        present(importMenu, animated: true, completion: nil)
    }
    
    @IBAction func setNumberOfBuffers(_ sender: UIButton) {
        let alertController = UIAlertController(title: "Number of Buffers", message: nil, preferredStyle: .actionSheet)
        let values = [2, 3, 4, 5, 6]
        values.forEach { value in
            let title = value == values.first ? "Disabled" : "\(value)"
            alertController.addAction(UIAlertAction(title: title, style: .default) {
                action in
                self.dfuNumberOfBuffers.text = value == 2 ? "Disabled" : "\(value)"
                // Pipeline Depth = Number of Buffers - 1
                self.uploadConfiguration.pipelineDepth = value - 1
            })
        }
        present(alertController, addingCancelAction: true)
    }
    
    @IBAction func setDfuAlignment(_ sender: UIButton) {
        let alertController = UIAlertController(title: "Byte Alignment", message: nil, preferredStyle: .actionSheet)
        ImageUploadAlignment.allCases.forEach { alignmentValue in
            alertController.addAction(UIAlertAction(title: alignmentValue.description, style: .default) {
                action in
                self.dfuByteAlignment.text = alignmentValue.description
                self.uploadConfiguration.byteAlignment = alignmentValue
            })
        }
        present(alertController, addingCancelAction: true)
    }
    
    @IBAction func setChunkSize(_ sender: Any) {
        let alertController = UIAlertController(title: "Set Chunk Size", message: "0 means Default (MTU Size)", preferredStyle: .alert)
        alertController.addTextField { (textField) in
            textField.placeholder = "\(self.uploadConfiguration.reassemblyBufferSize)"
            textField.keyboardType = .decimalPad
        }
        alertController.addAction(UIAlertAction(title: "Submit", style: .default, handler: { [weak alertController] (_) in
            guard let textField = alertController?.textFields?.first,
                  let stringValue = textField.text else { return }
            self.uploadConfiguration.reassemblyBufferSize = UInt64(stringValue) ?? 0
            self.dfuChunkSize.text = "\(self.uploadConfiguration.reassemblyBufferSize)"
        }))

        present(alertController, addingCancelAction: true)
    }
    
    private func present(_ alertViewController: UIAlertController, addingCancelAction addCancelAction: Bool = false) {
        if addCancelAction {
            alertViewController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        }
        
        // If the device is an ipad set the popover presentation controller
        if let presenter = alertViewController.popoverPresentationController {
            presenter.sourceView = self.view
            presenter.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            presenter.permittedArrowDirections = []
        }
        present(alertViewController, animated: true)
    }
    
    static let uploadImages = [0, 1, 2, 3]
    @IBAction func start(_ sender: UIButton) {
        guard let package = package else { return }
        uploadImageSize = nil
        
        let images: [ImageManager.Image]
        if package.images.count > 1 {
            images = package.images.map { ImageManager.Image(image: $0.image, data: $0.data) }
        } else {
            images = Self.uploadImages.map { ImageManager.Image(image: $0, data: package.images[0].data) }
        }
        
        let alertController = UIAlertController(title: "Select Core Slot", message: nil, preferredStyle: .actionSheet)
        let configuration = uploadConfiguration
        for image in images {
            alertController.addAction(UIAlertAction(title: McuMgrPackage.imageName(at: image.image), style: .default) { [weak self]
                action in
                self?.actionBuffers.isEnabled = false
                self?.actionAlignment.isEnabled = false
                self?.actionChunks.isEnabled = false
                self?.actionStart.isHidden = true
                self?.actionPause.isHidden = false
                self?.actionCancel.isHidden = false
                self?.actionSelect.isEnabled = false
                self?.imageSlot = image.image
                self?.status.textColor = .primary
                self?.status.text = "UPLOADING \(McuMgrPackage.imageName(at: image.image))..."
                _ = self?.imageManager.upload(images: [ImageManager.Image(image: image.image, data: image.data)],
                                              using: configuration, delegate: self)
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
        dfuSpeed.isHidden = true
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
        uploadImageSize = nil
        imageManager.continueUpload()
    }
    @IBAction func cancel(_ sender: UIButton) {
        dfuSpeed.isHidden = true
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
    private var initialBytes: Int = 0
    private var uploadConfiguration = FirmwareUpgradeConfiguration(estimatedSwapTime: 10.0, pipelineDepth: 1, byteAlignment: .disabled)
    private var uploadImageSize: Int!
    private var uploadTimestamp: Date!
}

// MARK: - ImageUploadDelegate

extension FirmwareUploadViewController: ImageUploadDelegate {
    
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        dfuSpeed.isHidden = false
        
        if uploadImageSize == nil || uploadImageSize != imageSize {
            uploadTimestamp = timestamp
            uploadImageSize = imageSize
            initialBytes = bytesSent
            progress.setProgress(Float(bytesSent) / Float(imageSize), animated: false)
        } else {
            progress.setProgress(Float(bytesSent) / Float(imageSize), animated: true)
        }
        
        // Date.timeIntervalSince1970 returns seconds
        let msSinceUploadBegan = max((timestamp.timeIntervalSince1970 - uploadTimestamp.timeIntervalSince1970) * 1000, 1)
        
        guard bytesSent < imageSize else {
            let averageSpeedInKiloBytesPerSecond = Double(imageSize - initialBytes) / msSinceUploadBegan
            dfuSpeed.text = "\(imageSize) bytes sent (avg \(String(format: "%.2f kB/s", averageSpeedInKiloBytesPerSecond)))"
            return
        }
        
        let bytesSentSinceUploadBegan = bytesSent - initialBytes
        // bytes / ms = kB/s
        let speedInKiloBytesPerSecond = Double(bytesSentSinceUploadBegan) / msSinceUploadBegan
        dfuSpeed.text = String(format: "%.2f kB/s", speedInKiloBytesPerSecond)
    }
    
    func uploadDidFail(with error: Error) {
        progress.setProgress(0, animated: true)
        actionBuffers.isEnabled = true
        actionAlignment.isEnabled = true
        actionChunks.isEnabled = true
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
        actionBuffers.isEnabled = true
        actionAlignment.isEnabled = true
        actionChunks.isEnabled = true
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
        actionBuffers.isEnabled = true
        actionAlignment.isEnabled = true
        actionChunks.isEnabled = true
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
            
            dfuNumberOfBuffers.text = uploadConfiguration.pipelineDepth == 1 ? "Disabled" : "\(uploadConfiguration.pipelineDepth + 1)"
            dfuByteAlignment.text = uploadConfiguration.byteAlignment.description
            dfuChunkSize.text = "\(uploadConfiguration.reassemblyBufferSize)"
            
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
