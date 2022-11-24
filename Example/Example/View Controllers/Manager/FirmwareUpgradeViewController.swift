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
    @IBOutlet weak var actionBuffers: UIButton!
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
    @IBOutlet weak var dfuNumberOfBuffers: UILabel!
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
    
    @IBAction func setNumberOfBuffers(_ sender: UIButton) {
        setPipelineDepth()
    }
    
    @IBAction func byteAlignment(_ sender: UIButton) {
        setByteAlignment()
    }
    
    @IBAction func start(_ sender: UIButton) {
        guard canStartUpload() else { return }
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
        guard canStartUpload() else { return }
        
        uploadTimestamp = nil
        uploadImageSize = nil
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
        }
    }
    
    // nRF52840 requires ~ 10 seconds for swapping images.
    // Adjust this parameter for your device.
    private var dfuManagerConfiguration = FirmwareUpgradeConfiguration(
        estimatedSwapTime: 10.0, eraseAppSettings: true, pipelineDepth: 3, byteAlignment: .fourByte)
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
                self.dfuManagerConfiguration.estimatedSwapTime = TimeInterval(numberOfSeconds)
                self.dfuSwapTime.text = "\(self.dfuManagerConfiguration.estimatedSwapTime)s"
            })
        }
        present(alertController, addingCancelAction: true)
    }
    
    private func setPipelineDepth() {
        let alertController = UIAlertController(title: "Number of Buffers", message: nil, preferredStyle: .actionSheet)
        let values = [2, 3, 4, 5, 6]
        values.forEach { value in
            let title = value == values.first ? "Disabled" : "\(value)"
            alertController.addAction(UIAlertAction(title: title, style: .default) {
                action in
                self.dfuNumberOfBuffers.text = value == 2 ? "Disabled" : "\(value)"
                // Pipeline Depth = Number of Buffers - 1
                self.dfuManagerConfiguration.pipelineDepth = value - 1
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
    
    private func canStartUpload() -> Bool {
        guard dfuManagerConfiguration.pipelineDepth == 1 || dfuManagerConfiguration.byteAlignment != .disabled else {
            
            dfuManagerConfiguration.byteAlignment = FirmwareUpgradeConfiguration().byteAlignment
            dfuByteAlignment.text = dfuManagerConfiguration.byteAlignment.description
            
            let alert = UIAlertController(title: "Byte Alignment Setting Changed", message: """
            Pipelining requires a Byte Alignment setting to be applied, otherwise chunk offsets can't be predicted as more Data is sent.
            """, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert)
            return false
        }
        return true
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
        actionBuffers.isHidden = true
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
        case .none:
            status.text = ""
        case .requestMcuMgrParameters:
            status.text = "REQUESTING MCUMGR PARAMETERS..."
        case .validate:
            status.text = "VALIDATING..."
        case .upload:
            status.text = "UPLOADING..."
        case .eraseAppSettings:
            status.text = "ERASING APP SETTINGS..."
        case .test:
            status.text = "TESTING..."
        case .confirm:
            status.text = "CONFIRMING..."
        case .reset:
            status.text = "RESETTING..."
        case .success:
            status.text = "UPLOAD COMPLETE"
        }
    }
    
    func upgradeDidComplete() {
        progress.setProgress(0, animated: false)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionSwap.isHidden = false
        actionBuffers.isHidden = false
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
        actionBuffers.isHidden = false
        actionAlignment.isHidden = false
        actionStart.isHidden = false
        
        actionSelect.isEnabled = true
        eraseSwitch.isEnabled = true
        status.textColor = .systemRed
        status.text = "\(error.localizedDescription)"
        status.numberOfLines = 0
        dfuSpeed.isHidden = true
    }
    
    func upgradeDidCancel(state: FirmwareUpgradeState) {
        progress.setProgress(0, animated: true)
        actionPause.isHidden = true
        actionResume.isHidden = true
        actionCancel.isHidden = true
        actionSwap.isHidden = false
        actionBuffers.isHidden = false
        actionAlignment.isHidden = false
        actionStart.isHidden = false
        actionSelect.isEnabled = true
        eraseSwitch.isEnabled = true
        status.textColor = .primary
        status.text = "CANCELLED"
        status.numberOfLines = 0
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
            status.numberOfLines = 0
            actionStart.isEnabled = true
            
            dfuSwapTime.text = "\(dfuManagerConfiguration.estimatedSwapTime)s"
            dfuSwapTime.numberOfLines = 0
            dfuNumberOfBuffers.text = dfuManagerConfiguration.pipelineDepth == 1 ? "Disabled" : "\(dfuManagerConfiguration.pipelineDepth + 1)"
            dfuNumberOfBuffers.numberOfLines = 0
            dfuByteAlignment.text = dfuManagerConfiguration.byteAlignment.description
            dfuByteAlignment.numberOfLines = 0
        } catch {
            print("Error reading hash: \(error)")
            fileName.text = url.lastPathComponent
            fileSize.text = ""
            fileHash.text = ""
            status.textColor = .systemRed
            status.text = "Error Loading File: \(error.localizedDescription)"
            status.numberOfLines = 0
            actionStart.isEnabled = false
        }
    }
}
