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
        let supportedDocumentTypes = ["com.apple.macbinary-archive", "public.zip-archive", "com.pkware.zip-archive", "com.apple.font-suitcase"]
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
        if let package {
            selectMode(for: package)
        } else if let envelope {
            // SUIT has "no mode" to select
            // (We use modes in the code only, but SUIT has no concept of upload modes)
            startFirmwareUpgrade(envelope: envelope)
        }
    }
    
    @IBAction func pause(_ sender: UIButton) {
        dfuManager.pause()
        actionPause.isHidden = true
        actionResume.isHidden = false
        status.text = "PAUSED"
        dfuSpeed.isHidden = true
    }
    
    @IBAction func resume(_ sender: UIButton) {
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
    private var envelope: McuMgrSuitEnvelope?
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.translatesAutoresizingMaskIntoConstraints = false
    }
    
    // MARK: - Logic
    
    private func setSwapTime() {
        let alertController = UIAlertController(title: "Swap time (in seconds)", message: nil, preferredStyle: .actionSheet)
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
        let alertController = UIAlertController(title: "Number of buffers", message: nil, preferredStyle: .actionSheet)
        let values = [2, 3, 4, 5, 6, 7, 8]
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
        let alertController = UIAlertController(title: "Byte alignment", message: nil, preferredStyle: .actionSheet)
        ImageUploadAlignment.allCases.forEach { alignmentValue in
            let text = "\(alignmentValue)"
            alertController.addAction(UIAlertAction(title: text, style: .default) {
                action in
                self.dfuByteAlignment.text = text
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
            let text = "\(upgradeMode)"
            alertController.addAction(UIAlertAction(title: text, style: .default) {
                action in
                self.dfuManagerConfiguration.upgradeMode = upgradeMode
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
            dfuManagerConfiguration.suitMode = false
            try dfuManager.start(images: package.images, using: dfuManagerConfiguration)
        } catch {
            status.textColor = .systemRed
            status.text = error.localizedDescription
            actionStart.isEnabled = false
        }
    }
    
    private func startFirmwareUpgrade(envelope: McuMgrSuitEnvelope) {
        do {
            // sha256 is the currently only supported mode.
            // The rest are optional to implement in SUIT.
            guard let sha256Hash = envelope.digest.hash(for: .sha256) else {
                throw McuMgrSuitParseError.supportedAlgorithmNotFound
            }
            
            dfuManagerConfiguration.suitMode = true
            dfuManagerConfiguration.upgradeMode = .uploadOnly
            try dfuManager.start(hash: sha256Hash, data: envelope.data, using: dfuManagerConfiguration)
        } catch {
            status.textColor = .systemRed
            status.text = error.localizedDescription
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
        status.textColor = .secondary
        switch newState {
        case .none:
            status.text = ""
        case .requestMcuMgrParameters:
            status.text = "REQUESTING MCUMGR PARAMETERS..."
        case .bootloaderInfo:
            status.text = "REQUESTING BOOTLOADER INFO..."
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
        status.text = error.localizedDescription
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
        self.package = nil
        self.envelope = nil
        
        switch parseAsMcuMgrPackage(url) {
        case .success(let package):
            self.package = package
        case .failure(let error):
            if error is McuMgrPackage.Error {
                switch parseAsSuitEnvelope(url) {
                case .success(let envelope):
                    self.envelope = envelope
                case .failure(let error):
                    onParseError(error, for: url)
                }
            } else {
                onParseError(error, for: url)
            }
        }
        (parent as! ImageController).innerViewReloaded()
    }
    
    // MARK: - Private
    
    func parseAsMcuMgrPackage(_ url: URL) -> Result<McuMgrPackage, Error> {
        do {
            let package = try McuMgrPackage(from: url)
            fileName.text = url.lastPathComponent
            fileSize.text = package.sizeString()
            fileSize.numberOfLines = 0
            fileHash.text = try package.hashString()
            fileHash.numberOfLines = 0
            
            status.textColor = .secondary
            status.text = "READY"
            status.numberOfLines = 0
            actionStart.isEnabled = true
            
            dfuSwapTime.text = "\(dfuManagerConfiguration.estimatedSwapTime)s"
            dfuSwapTime.numberOfLines = 0
            dfuNumberOfBuffers.text = dfuManagerConfiguration.pipelineDepth == 1 ? "Disabled" : "\(dfuManagerConfiguration.pipelineDepth + 1)"
            dfuNumberOfBuffers.numberOfLines = 0
            dfuByteAlignment.text = "\(dfuManagerConfiguration.byteAlignment)"
            dfuByteAlignment.numberOfLines = 0
            
            return .success(package)
        } catch {
            return .failure(error)
        }
    }
    
    func parseAsSuitEnvelope(_ url: URL) -> Result<McuMgrSuitEnvelope, Error> {
        do {
            let envelope = try McuMgrSuitEnvelope(from: url)
            fileName.text = url.lastPathComponent
            fileSize.text = envelope.sizeString()
            fileSize.numberOfLines = 0
            fileHash.text = envelope.digest.hashString()
            fileHash.numberOfLines = 0
            
            status.textColor = .secondary
            status.text = "READY"
            status.numberOfLines = 0
            actionStart.isEnabled = true
            
            dfuSwapTime.text = "\(dfuManagerConfiguration.estimatedSwapTime)s"
            dfuSwapTime.numberOfLines = 0
            dfuNumberOfBuffers.text = dfuManagerConfiguration.pipelineDepth == 1 ? "Disabled" : "\(dfuManagerConfiguration.pipelineDepth + 1)"
            dfuNumberOfBuffers.numberOfLines = 0
            dfuByteAlignment.text = "\(dfuManagerConfiguration.byteAlignment)"
            dfuByteAlignment.numberOfLines = 0
            return .success(envelope)
        } catch {
            return .failure(error)
        }
    }
    
    func onParseError(_ error: Error, for url: URL) {
        self.package = nil
        envelope = nil
        fileName.text = url.lastPathComponent
        fileSize.text = ""
        fileHash.text = ""
        status.textColor = .systemRed
        status.text = error.localizedDescription
        status.numberOfLines = 0
        actionStart.isEnabled = false
    }
}
