/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import McuManager

class FirmwareUpgradeViewController: UIViewController, McuMgrViewController {
    
    @IBOutlet weak var actionSelect: UIButton!
    @IBOutlet weak var actionStart: UIButton!
    @IBOutlet weak var actionPause: UIButton!
    @IBOutlet weak var actionResume: UIButton!
    @IBOutlet weak var actionCancel: UIButton!
    @IBOutlet weak var status: UILabel!
    @IBOutlet weak var fileName: UILabel!
    @IBOutlet weak var fileSize: UILabel!
    @IBOutlet weak var fileHash: UILabel!
    @IBOutlet weak var progress: UIProgressView!
    
    @IBAction func selectFirmware(_ sender: UIButton) {
        let importMenu = UIDocumentMenuViewController(documentTypes: ["public.data", "public.content"],
                                                      in: .import)
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = actionSelect
        present(importMenu, animated: true, completion: nil)
    }
    @IBAction func start(_ sender: UIButton) {
        selectMode(for: imageData!)
    }
    @IBAction func pause(_ sender: UIButton) {
        dfuManager.pause()
        actionPause.isHidden = true
        actionResume.isHidden = false
        status.text = "PAUSED"
    }
    @IBAction func resume(_ sender: UIButton) {
        dfuManager.resume()
        actionPause.isHidden = false
        actionResume.isHidden = true
        status.text = "UPLOADING..."
    }
    @IBAction func cancel(_ sender: UIButton) {
        dfuManager.cancel()
    }
    
    private var imageData: Data?
    private var dfuManager: FirmwareUpgradeManager!
    var transporter: McuMgrTransport! {
        didSet {
            dfuManager = FirmwareUpgradeManager(transporter: transporter, delegate: self)
            dfuManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            // nRF52840 requires ~ 10 seconds for swapping images.
            // Adjust this parameter for your device.
            dfuManager.estimatedSwapTime = 10.0
        }
    }
    
    private func selectMode(for imageData: Data) {
        let alertController = UIAlertController(title: "Select mode", message: nil, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: "Test and confirm", style: .default) {
            action in
            self.dfuManager!.mode = .testAndConfirm
            self.startFirmwareUpgrade(imageData: imageData)
        })
        alertController.addAction(UIAlertAction(title: "Test only", style: .default) {
            action in
            self.dfuManager!.mode = .testOnly
            self.startFirmwareUpgrade(imageData: imageData)
        })
        alertController.addAction(UIAlertAction(title: "Confirm only", style: .default) {
            action in
            self.dfuManager!.mode = .confirmOnly
            self.startFirmwareUpgrade(imageData: imageData)
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    
        // If the device is an ipad set the popover presentation controller
        if let presenter = alertController.popoverPresentationController {
        presenter.sourceView = self.view
        presenter.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        presenter.permittedArrowDirections = []
        }
        present(alertController, animated: true)
    }
    
    private func startFirmwareUpgrade(imageData: Data) {
        do {
            try dfuManager.start(data: imageData)
        } catch {
            print("Error reading hash: \(error)")
            status.textColor = .systemRed
            status.text = "ERROR"
            actionStart.isEnabled = false
        }
    }
}

// MARK: - Firmware Upgrade Delegate
extension FirmwareUpgradeViewController: FirmwareUpgradeDelegate {
    
    func upgradeDidStart(controller: FirmwareUpgradeController) {
        actionStart.isHidden = true
        actionPause.isHidden = false
        actionCancel.isHidden = false
        actionSelect.isEnabled = false
    }
    
    func upgradeStateDidChange(from previousState: FirmwareUpgradeState, to newState: FirmwareUpgradeState) {
        status.textColor = .primary
        switch newState {
        case .validate:
            status.text = "VALIDATING..."
        case .upload:
            status.text = "UPLOADING..."
        case .test:
            status.text = "TESTING..."
        case .confirm:
            status.text = "CONFIRMING..."
        case .reset:
            status.text = "RESETTING..."
        case .success:
            status.text = "UPLOAD COMPLETE"
        default:
            status.text = ""
        }
    }
    
    func upgradeDidComplete() {
        progress.setProgress(0, animated: false)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionStart.isHidden = false
        actionStart.isEnabled = false
        actionSelect.isEnabled = true
        imageData = nil
    }
    
    func upgradeDidFail(inState state: FirmwareUpgradeState, with error: Error) {
        progress.setProgress(0, animated: true)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionStart.isHidden = false
        actionSelect.isEnabled = true
        status.textColor = .systemRed
        status.text = "\(error.localizedDescription)"
    }
    
    func upgradeDidCancel(state: FirmwareUpgradeState) {
        progress.setProgress(0, animated: true)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionStart.isHidden = false
        actionSelect.isEnabled = true
        status.textColor = .primary
        status.text = "CANCELLED"
    }
    
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        progress.setProgress(Float(bytesSent) / Float(imageSize), animated: true)
    }
}

// MARK: - Document Picker
extension FirmwareUpgradeViewController: UIDocumentMenuDelegate, UIDocumentPickerDelegate {
    
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
