/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary
import iOSOtaLibrary
import UniformTypeIdentifiers

// MARK: - FirmwareUpgradeViewController

final class FirmwareUpgradeViewController: UIViewController, McuMgrViewController {
    
    // MARK: @IBOutlet(s)
    
    @IBOutlet weak var actionSwap: UIButton!
    @IBOutlet weak var actionBuffers: UIButton!
    @IBOutlet weak var actionAlignment: UIButton!
    @IBOutlet weak var actionSelect: UIButton!
    @IBOutlet weak var actionCheckForUpdates: UIButton!
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
    
    // MARK: @IBAction(s)
    
    @IBAction func selectFirmware(_ sender: UIButton) {
        let supportedDocumentTypes = ["com.apple.macbinary-archive", "public.zip-archive", "com.pkware.zip-archive", "com.apple.font-suitcase"]
        let importMenu = UIDocumentPickerViewController(documentTypes: supportedDocumentTypes,
                                                        in: .import)
        importMenu.allowsMultipleSelection = false
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = actionSelect
        present(importMenu, animated: true, completion: nil)
    }
    
    @IBAction func checkForUpdates(_ sender: UIButton) {
        guard let imageController = parent as? ImageController else { return }
        
        otaManager = OTAManager()
        baseController?.onDeviceStatusReady { [unowned self] in
            switch imageController.otaStatus {
            case .unsupported:
                let alertController = UIAlertController(title: "nRF Cloud Update Unavailable", message: "This device does not support nRF Cloud OTA Updates.", preferredStyle: .alert)
                baseController?.present(alertController, addingCancelAction: true, cancelActionTitle: "OK")
            case .missingProjectKey(let deviceInfo, _):
                setProjectKey(for: deviceInfo)
            case .supported(let deviceInfo, let projectKey):
                requestLatestReleaseInfo(for: deviceInfo, using: projectKey)
            case .none:
                break
            }
        }
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
        baseController?.onDeviceStatusReady { [unowned self] in
            startPackageDFU()
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
    
    // MARK: Private Properties
    
    private var package: McuMgrPackage?
    private var dfuManager: FirmwareUpgradeManager!
    var transport: McuMgrTransport! {
        didSet {
            dfuManager = FirmwareUpgradeManager(transport: transport, delegate: self)
            dfuManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    
    // nRF52840 requires ~ 10 seconds for swapping images.
    // Adjust this parameter for your device.
    private var dfuManagerConfiguration = FirmwareUpgradeConfiguration(
        estimatedSwapTime: 10.0, eraseAppSettings: false, pipelineDepth: 3, byteAlignment: .fourByte)
    private var initialBytes: Int = 0
    private var uploadImageSize: Int!
    private var uploadTimestamp: Date!
    private var otaManager: OTAManager?
    
    private var baseController: BaseViewController? {
        guard let imageController = parent as? ImageController,
              let baseController = imageController.parent as? BaseViewController else { return nil }
        return baseController
    }
    
    // MARK: viewDidLoad()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.translatesAutoresizingMaskIntoConstraints = false
        restoreBasicSettings()
    }
    
    // MARK: Logic
    
    private func setSwapTime() {
        let alertController = UIAlertController(title: "Swap time (in seconds)", message: nil, preferredStyle: .actionSheet)
        let seconds = [0, 5, 10, 20, 30, 40]
        seconds.forEach { numberOfSeconds in
            alertController.addAction(UIAlertAction(title: "\(numberOfSeconds) seconds", style: .default) { [unowned self] action in
                self.updateEstimatedSwapTime(to: numberOfSeconds)
            })
        }
        baseController?.present(alertController, addingCancelAction: true)
    }
    
    private func setPipelineDepth() {
        let alertController = UIAlertController(title: "Number of buffers", message: nil, preferredStyle: .actionSheet)
        let values = [2, 3, 4, 5, 6, 7, 8]
        values.forEach { value in
            let title = value == values.first ? "Disabled" : "\(value)"
            alertController.addAction(UIAlertAction(title: title, style: .default) { [unowned self]
                action in
                self.updatePipelineDepth(to: value)
            })
        }
        baseController?.present(alertController, addingCancelAction: true)
    }
    
    private func setByteAlignment() {
        let alertController = UIAlertController(title: "Byte Alignment", message: nil, preferredStyle: .actionSheet)
        ImageUploadAlignment.allCases.forEach { alignmentValue in
            let text = "\(alignmentValue)"
            alertController.addAction(UIAlertAction(title: text, style: .default) { [unowned self]
                action in
                self.updateByteAlignment(to: alignmentValue)
            })
        }
        baseController?.present(alertController, addingCancelAction: true)
    }
    
    private func setProjectKey(for deviceInfo: DeviceInfoToken) {
        let alertController = UIAlertController(title: "Missing Project Key", message: "nRF Cloud Project Key is required to continue.", preferredStyle: .alert)
        alertController.addTextField()
        alertController.addAction(UIAlertAction(title: "Continue", style: .default) { [unowned self] action in
            guard let textField = alertController.textFields?.first,
                  let keyString = textField.text else { return }
            let key = ProjectKey(keyString)
            requestLatestReleaseInfo(for: deviceInfo, using: key)
        })
        baseController?.present(alertController, addingCancelAction: true)
    }
    
    // MARK: requestLatestReleaseInfo(for:using:)
    
    private func requestLatestReleaseInfo(for deviceInfo: DeviceInfoToken,
                                          using projectKey: ProjectKey) {
        otaManager?.getLatestReleaseInfo(deviceInfo: deviceInfo, projectKey: projectKey) { [unowned self] result in
            switch result {
            case .success(let resultInfo):
                let alertController = UIAlertController(title: "OTA Update Available", message: nil, preferredStyle: .alert)
                let artifact: ReleaseArtifact! = resultInfo.artifacts.first
                let revisionString = resultInfo.revision.isEmpty ? "" : "-\(resultInfo.revision)"
                alertController.message = """
                Firmware version \(resultInfo.version)\(revisionString) (\(artifact.sizeString())) is available with the following release notes:
                
                \(resultInfo.notes)
                """
                alertController.addAction(UIAlertAction(title: "Download", style: .default) { [unowned self] action in
                    download(release: resultInfo)
                })
                baseController?.present(alertController, addingCancelAction: true)
            case .failure(let otaError):
                handleLatestReleaseError(otaError)
            }
        }
    }
    
    private func handleLatestReleaseError(_ otaError: OTAManagerError) {
        switch otaError {
        case .networkError:
            let alertController = UIAlertController(title: "Network Error", message: "Unable to reach the Network.", preferredStyle: .alert)
            baseController?.present(alertController, addingCancelAction: true,
                                    cancelActionTitle: "OK")
        case .deviceIsUpToDate:
            let alertController = UIAlertController(title: "Your device is up to date", message: "Your device is already using the latest firmware version available through nRF Cloud OTA.", preferredStyle: .alert)
            baseController?.present(alertController, addingCancelAction: true,
                                    cancelActionTitle: "OK")
        default:
            let alertController = UIAlertController(title: "Error Requesting Update", message: otaError.localizedDescription, preferredStyle: .alert)
            baseController?.present(alertController, addingCancelAction: true, cancelActionTitle: "OK")
        }
    }
    
    private func download(release: LatestReleaseInfo) {
        let artifact: ReleaseArtifact! = release.artifacts.first
        otaManager?.download(artifact: artifact) { [unowned self] result in
            switch result {
            case .success(let fileURL):
                select(fileURL)
            case .failure(let error):
                guard let url = artifact.releaseURL() else { return }
                onParseError(error, for: url)
            }
        }
    }
    
    private func select(_ url: URL) {
        self.package = nil
        
        switch parseAsMcuMgrPackage(url) {
        case .success(let package):
            self.package = package
        case .failure(let error):
            onParseError(error, for: url)
        }
        (parent as? ImageController)?.innerViewReloaded()
    }
    
    private func startPackageDFU() {
        guard let package else { return }
        if package.isForSUIT {
            // SUIT has "no mode" to select
            // (We use modes in the code only, but SUIT has no concept of upload modes)
            startFirmwareUpgrade(package: package)
        } else {
            if package.images.count > 1, package.images.contains(where: { $0.content == .mcuboot }) {
                // Force user to select which 'image' to use for bootloader update.
                selectBootloaderImage(for: package)
            } else {
                selectMode(for: package)
            }
        }
    }
    
    @IBAction func setEraseApplicationSettings(_ sender: UISwitch) {
        updateEraseApplicationSettings(to: sender.isOn)
    }
    
    // MARK: selectMode(for:)
    
    private func selectMode(for package: McuMgrPackage) {
        let alertController = UIAlertController(title: "Select Mode", message: nil, preferredStyle: .actionSheet)
        FirmwareUpgradeMode.allCases.forEach { upgradeMode in
            let text = "\(upgradeMode)"
            alertController.addAction(UIAlertAction(title: text, style: .default) {
                action in
                self.dfuManagerConfiguration.upgradeMode = upgradeMode
                self.startFirmwareUpgrade(package: package)
            })
        }
        baseController?.present(alertController, addingCancelAction: true)
    }
    
    // MARK: selectBootloaderImage(for:)
    
    private func selectBootloaderImage(for package: McuMgrPackage) {
        let alertController = buildSelectImageController()
        for image in package.images {
            alertController.addAction(UIAlertAction(title: image.imageName(), style: .default) { [weak self]
                action in
                self?.dfuManagerConfiguration.eraseAppSettings = false
                self?.dfuManagerConfiguration.upgradeMode = .confirmOnly
                self?.startFirmwareUpgrade(images: [image])
            })
        }
        present(alertController, animated: true)
    }
    
    // MARK: updateEstimatedSwapTime(to:)
    
    private func updateEstimatedSwapTime(to numberOfSeconds: Int, updatingUserDefaults: Bool = true) {
        dfuManagerConfiguration.estimatedSwapTime = TimeInterval(numberOfSeconds)
        dfuSwapTime.text = "\(dfuManagerConfiguration.estimatedSwapTime)s"
        guard updatingUserDefaults else { return }
        UserDefaults.standard.set(numberOfSeconds, forKey: Key.swapTime.rawValue)
    }
    
    // MARK: updatePipelineDepth(to:)
    
    private func updatePipelineDepth(to value: Int, updatingUserDefaults: Bool = true) {
        dfuNumberOfBuffers.text = value == 2 ? "Disabled" : "\(value)"
        // Pipeline Depth = Number of Buffers - 1
        dfuManagerConfiguration.pipelineDepth = value - 1
        guard updatingUserDefaults else { return }
        UserDefaults.standard.set(dfuManagerConfiguration.pipelineDepth,
                                  forKey: Key.pipelineDepth.rawValue)
    }
    
    // MARK: updateByteAlignment(to:)
    
    private func updateByteAlignment(to byteAlignment: ImageUploadAlignment, updatingUserDefaults: Bool = true) {
        dfuByteAlignment.text = "\(byteAlignment)"
        dfuManagerConfiguration.byteAlignment = byteAlignment
        guard updatingUserDefaults else { return }
        UserDefaults.standard.set(byteAlignment.rawValue, forKey: Key.byteAlignment.rawValue)
    }
    
    // MARK: updateEraseApplicationSettings(to:)
    
    private func updateEraseApplicationSettings(to eraseApplicationSettings: Bool, updatingUserDefaults: Bool = true) {
        eraseSwitch.isOn = eraseApplicationSettings
        dfuManagerConfiguration.eraseAppSettings = eraseApplicationSettings
        guard updatingUserDefaults else { return }
        UserDefaults.standard.set(eraseApplicationSettings,
                                  forKey: Key.eraseAppSettings.rawValue)
    }
    
    // MARK: startFirmwareUpgrade
    
    private func startFirmwareUpgrade(package: McuMgrPackage) {
        dfuManager.start(package: package, using: dfuManagerConfiguration)
    }
    
    private func startFirmwareUpgrade(images: [ImageManager.Image]) {
        dfuManager.start(images: images, using: dfuManagerConfiguration)
    }
}

// MARK: - UserDefaults Keys

fileprivate extension FirmwareUpgradeViewController {
    
    enum Key: String, RawRepresentable {
        case swapTime = "basic_SwapTime"
        case pipelineDepth = "basic_PipelineDepth"
        case byteAlignment = "basic_ByteAlignment"
        case eraseAppSettings = "basic_EraseSettings"
    }
    
    private func restoreBasicSettings() {
        if UserDefaults.standard.object(forKey: Key.swapTime.rawValue) != nil {
            let swapTime = UserDefaults.standard.integer(forKey: Key.swapTime.rawValue)
            updateEstimatedSwapTime(to: swapTime, updatingUserDefaults: false)
        }
        
        if UserDefaults.standard.object(forKey: Key.pipelineDepth.rawValue) != nil {
            let pipelineDepth = UserDefaults.standard.integer(forKey: Key.pipelineDepth.rawValue)
            updatePipelineDepth(to: pipelineDepth + 1, updatingUserDefaults: false)
        }
        
        if UserDefaults.standard.object(forKey: Key.byteAlignment.rawValue) != nil {
            let rawByte = UserDefaults.standard.integer(forKey: Key.byteAlignment.rawValue)
            if let byteAlignment = ImageUploadAlignment(rawValue: UInt64(rawByte)) {
                updateByteAlignment(to: byteAlignment, updatingUserDefaults: false)
            }
        }
        
        if UserDefaults.standard.object(forKey: Key.eraseAppSettings.rawValue) != nil {
            let eraseAppSettings = UserDefaults.standard.bool(forKey: Key.eraseAppSettings.rawValue)
            updateEraseApplicationSettings(to: eraseAppSettings, updatingUserDefaults: false)
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
        actionCheckForUpdates.isEnabled = false
        eraseSwitch.isEnabled = false
        
        initialBytes = 0
        uploadImageSize = nil
        
        baseController?.onDFUStart()
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
        actionCheckForUpdates.isEnabled = true
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
        actionCheckForUpdates.isEnabled = true
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
        actionCheckForUpdates.isEnabled = true
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

// MARK: - Suit Upgrade Delegate

extension FirmwareUpgradeViewController: SuitFirmwareUpgradeDelegate {
    
    func uploadRequestsResource(_ resource: FirmwareUpgradeResource) {
        guard let package else { return }
        guard let resourceImage = package.image(forResource: resource) else {
            upgradeDidFail(inState: .upload,
                           with: McuMgrPackage.Error.resourceNotFound(resource))
            return
        }
        dfuManager.uploadResource(resource, data: resourceImage.data)
    }
}

// MARK: - Document Picker

extension FirmwareUpgradeViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentAt url: URL) {
        select(url)
    }
    
    // MARK: - Private
    
    func parseAsMcuMgrPackage(_ url: URL) -> Result<McuMgrPackage, Error> {
        do {
            let package = try McuMgrPackage(from: url)
            fileName.text = url.lastPathComponent
            fileSize.text = package.sizeString()
            fileSize.numberOfLines = 0
            if let envelope = package.envelope {
                fileHash.text = envelope.digest.hashString()
            } else {
                fileHash.text = package.hashString()
            }
            fileHash.numberOfLines = 0
            
            status.textColor = .secondary
            status.text = "READY"
            status.numberOfLines = 0
            actionStart.isEnabled = true
            actionCheckForUpdates.isEnabled = true
            
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
    
    func onParseError(_ error: Error, for url: URL) {
        self.package = nil
        fileName.text = url.lastPathComponent
        fileSize.text = ""
        fileHash.text = ""
        status.textColor = .systemRed
        status.text = error.localizedDescription
        status.numberOfLines = 0
        actionStart.isEnabled = false
    }
}
