/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

final class FirmwareUpgradeViewController: UIViewController, McuMgrViewController {
    
    // MARK: - IBOutlet(s)
    
    @IBOutlet weak var actionSwap: UIButton!
    @IBOutlet weak var actionPipeline: UIButton!
    @IBOutlet weak var actionAlignment: UIButton!
    @IBOutlet weak var actionSelect: UIButton!
    @IBOutlet weak var actionStart: UIButton!
    @IBOutlet weak var actionPause: UIButton!
    @IBOutlet weak var actionResume: UIButton!
    @IBOutlet weak var actionCancel: UIButton!
    @IBOutlet weak var status: UILabel!
    @IBOutlet weak var fileName: UILabel!
    @IBOutlet weak var fileSize: UILabel!
    @IBOutlet weak var fileHash: UILabel!
    @IBOutlet weak var dfuSwapTime: UILabel!
    @IBOutlet weak var dfuPipelineDepth: UILabel!
    @IBOutlet weak var dfuByteAlignment: UILabel!
    @IBOutlet weak var eraseSwitch: UISwitch!
    @IBOutlet weak var dfuSpeed: UILabel!
    @IBOutlet weak var progress: UIProgressView!
    
    // MARK: - IBAction(s)
    
    @IBAction func selectFirmware(_ sender: UIButton) {
        let supportedDocumentTypes = ["com.apple.macbinary-archive", "public.zip-archive", "com.pkware.zip-archive"]
        let importMenu = UIDocumentMenuViewController(documentTypes: supportedDocumentTypes,
                                                      in: .import)
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = actionSelect
        present(importMenu, animated: true, completion: nil)
    }
    
    @IBAction func eraseApplicationSettingsChanged(_ sender: UISwitch) {
        dfuManagerConfiguration.eraseAppSettings = sender.isOn
    }
    
    @IBAction func swapTime(_ sender: UIButton) {
        setSwapTime()
    }
    
    @IBAction func setPipelienDepth(_ sender: UIButton) {
        setPipelineDepth()
    }
    
    @IBAction func byteAlignment(_ sender: UIButton) {
        setByteAlignment()
    }
    
    @IBAction func start(_ sender: UIButton) {
        selectMode(for: package!)
    }
    
    @IBAction func pause(_ sender: UIButton) {
        dfuManager.pause()
        actionPause.isHidden = true
        actionResume.isHidden = false
        status.text = "PAUSED"
        dfuSpeed.isHidden = true
    }
    
    @IBAction func resume(_ sender: UIButton) {
        dfuManager.resume()
        actionPause.isHidden = false
        actionResume.isHidden = true
        status.text = "UPLOADING..."
        dfuSpeed.isHidden = false
    }
    
    @IBAction func cancel(_ sender: UIButton) {
        dfuManager.cancel()
    }
    
    private var package: McuMgrPackage?
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
    private var dfuManagerConfiguration = FirmwareUpgradeConfiguration(
        eraseAppSettings: true, pipelineDepth: 3, byteAlignment: .fourByte)
    private var initialBytes: Int = 0
    private var uploadImageSize: Int!
    private var uploadTimestamp: Date!
    
    // MARK: - Logic
    
    private func setSwapTime() {
        let alertController = UIAlertController(title: "Swap Time (in seconds)", message: nil, preferredStyle: .actionSheet)
        let seconds = [0, 5, 10, 20, 30, 40]
        seconds.forEach { numberOfSeconds in
            alertController.addAction(UIAlertAction(title: "\(numberOfSeconds) seconds", style: .default) {
                action in
                self.dfuManager!.estimatedSwapTime = TimeInterval(numberOfSeconds)
                self.dfuSwapTime.text = "\(self.dfuManager!.estimatedSwapTime)s"
            })
        }
        present(alertController, addingCancelAction: true)
    }
    
    private func setPipelineDepth() {
        let alertController = UIAlertController(title: "Pipeline Depth", message: nil, preferredStyle: .actionSheet)
        let values = [1, 2, 3, 4]
        values.forEach { value in
            let title = value == values.first ? "1 (no Pipelining)" : "\(value)"
            alertController.addAction(UIAlertAction(title: title, style: .default) {
                action in
                self.dfuPipelineDepth.text = "\(value)"
                self.dfuManagerConfiguration.pipelineDepth = value
            })
        }
        present(alertController, addingCancelAction: true)
    }
    
    private func setByteAlignment() {
        let alertController = UIAlertController(title: "Byte Alignment", message: nil, preferredStyle: .actionSheet)
        ImageUploadAlignment.allCases.forEach { alignmentValue in
            alertController.addAction(UIAlertAction(title: alignmentValue.description, style: .default) {
                action in
                self.dfuByteAlignment.text = alignmentValue.description
                self.dfuManagerConfiguration.byteAlignment = alignmentValue
            })
        }
        present(alertController, addingCancelAction: true)
    }
    
    @IBAction func setEraseApplicationSettings(_ sender: UISwitch) {
        dfuManagerConfiguration.eraseAppSettings = sender.isOn
    }
    
    private func selectMode(for package: McuMgrPackage) {
        let alertController = UIAlertController(title: "Select mode", message: nil, preferredStyle: .actionSheet)
        FirmwareUpgradeMode.allCases.forEach { upgradeMode in
            alertController.addAction(UIAlertAction(title: upgradeMode.description, style: .default) {
                action in
                self.dfuManager!.mode = upgradeMode
                self.startFirmwareUpgrade(package: package)
            })
        }
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
    
    private func startFirmwareUpgrade(package: McuMgrPackage) {
        do {
            try dfuManager.start(images: package.images, using: dfuManagerConfiguration)
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
        actionSwap.isHidden = true
        actionPipeline.isHidden = true
        actionAlignment.isHidden = true
        actionStart.isHidden = true
        
        actionPause.isHidden = false
        actionCancel.isHidden = false
        actionSelect.isEnabled = false
        eraseSwitch.isEnabled = false
        
        initialBytes = 0
        uploadImageSize = nil
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
        actionSwap.isHidden = false
        actionPipeline.isHidden = false
        actionAlignment.isHidden = false
        actionStart.isHidden = false
        
        actionStart.isEnabled = false
        actionSelect.isEnabled = true
        eraseSwitch.isEnabled = true
        package = nil
    }
    
    func upgradeDidFail(inState state: FirmwareUpgradeState, with error: Error) {
        progress.setProgress(0, animated: true)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionSwap.isHidden = false
        actionPipeline.isHidden = false
        actionAlignment.isHidden = false
        actionStart.isHidden = false
        
        actionSelect.isEnabled = true
        eraseSwitch.isEnabled = true
        status.textColor = .systemRed
        status.text = "\(error.localizedDescription)"
        dfuSpeed.isHidden = true
    }
    
    func upgradeDidCancel(state: FirmwareUpgradeState) {
        progress.setProgress(0, animated: true)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionSwap.isHidden = false
        actionPipeline.isHidden = false
        actionAlignment.isHidden = false
        actionStart.isHidden = false
        actionSelect.isEnabled = true
        eraseSwitch.isEnabled = true
        status.textColor = .primary
        status.text = "CANCELLED"
        dfuSpeed.isHidden = true
    }
    
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
        let msSinceUploadBegan = (timestamp.timeIntervalSince1970 - uploadTimestamp.timeIntervalSince1970) * 1000
        
        guard bytesSent < imageSize else {
            let averageSpeedInKiloBytesPerSecond = Double(imageSize - initialBytes) / msSinceUploadBegan
            dfuSpeed.text = "\(imageSize - initialBytes) bytes sent (avg \(String(format: "%.2f kB/s", averageSpeedInKiloBytesPerSecond)))"
            return
        }
        
        let bytesSentSinceUploadBegan = bytesSent - initialBytes
        // bytes / ms = kB/s
        let speedInKiloBytesPerSecond = Double(bytesSentSinceUploadBegan) / msSinceUploadBegan
        dfuSpeed.text = String(format: "%.2f kB/s", speedInKiloBytesPerSecond)
    }
}

// MARK: - Document Picker

extension FirmwareUpgradeViewController: UIDocumentMenuDelegate, UIDocumentPickerDelegate {
    
    func documentMenu(_ documentMenu: UIDocumentMenuViewController, didPickDocumentPicker documentPicker: UIDocumentPickerViewController) {
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        do {
            package = try McuMgrPackage(from: url)
            fileName.text = url.lastPathComponent
            fileSize.text = package?.sizeString()
            fileSize.numberOfLines = 0
            fileHash.text = try package?.hashString()
            fileHash.numberOfLines = 0
            
            status.textColor = .primary
            status.text = "READY"
            actionStart.isEnabled = true
            
            dfuSwapTime.text = "\(dfuManager.estimatedSwapTime)s"
            dfuSwapTime.numberOfLines = 0
            dfuPipelineDepth.text = "\(dfuManagerConfiguration.pipelineDepth)"
            dfuPipelineDepth.numberOfLines = 0
            dfuByteAlignment.text = dfuManagerConfiguration.byteAlignment.description
            dfuByteAlignment.numberOfLines = 0
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
