/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary
import UniformTypeIdentifiers

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
        let supportedDocumentTypes = ["com.apple.macbinary-archive", "public.zip-archive", "com.pkware.zip-archive", "com.apple.font-suitcase"]
        let importMenu = UIDocumentPickerViewController(documentTypes: supportedDocumentTypes,
                                                        in: .import)
        importMenu.allowsMultipleSelection = false
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = actionSelect
        present(importMenu, animated: true, completion: nil)
    }
    
    @IBAction func setNumberOfBuffers(_ sender: UIButton) {
        let alertController = UIAlertController(title: "Number of buffers", message: nil, preferredStyle: .actionSheet)
        let values = [2, 3, 4, 5, 6, 7, 8]
        values.forEach { value in
            let title = value == values.first ? "Disabled" : "\(value)"
            alertController.addAction(UIAlertAction(title: title, style: .default) { [unowned self]
                action in
                self.updatePipelineDepth(to: value)
            })
        }
        present(alertController, addingCancelAction: true)
    }
    
    @IBAction func setDfuAlignment(_ sender: UIButton) {
        let alertController = UIAlertController(title: "Byte alignment", message: nil, preferredStyle: .actionSheet)
        ImageUploadAlignment.allCases.forEach { alignmentValue in
            let text = "\(alignmentValue)"
            alertController.addAction(UIAlertAction(title: text, style: .default) { [unowned self]
                action in
                self.updateByteAlignment(to: alignmentValue)
            })
        }
        present(alertController, addingCancelAction: true)
    }
    
    @IBAction func setChunkSize(_ sender: Any) {
        let alertController = UIAlertController(title: "Set chunk size", message: "0 means default (MTU size)", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "\(self.uploadConfiguration.reassemblyBufferSize)"
            textField.keyboardType = .decimalPad
        }
        alertController.addAction(UIAlertAction(title: "Submit", style: .default, handler: { [unowned alertController, unowned self] (_) in
            guard let textField = alertController.textFields?.first,
                  let stringValue = textField.text else { return }
            self.updateBufferSize(to: Int(stringValue) ?? 0)
        }))

        present(alertController, addingCancelAction: true)
    }
    
    // MARK: updatePipelineDepth(to:)
    
    private func updatePipelineDepth(to value: Int, updatingUserDefaults: Bool = true) {
        dfuNumberOfBuffers.text = value == 2 ? "Disabled" : "\(value)"
        // Pipeline Depth = Number of Buffers - 1
        uploadConfiguration.pipelineDepth = value - 1
        guard updatingUserDefaults else { return }
        UserDefaults.standard.set(uploadConfiguration.pipelineDepth,
                                  forKey: Key.pipelineDepth.rawValue)
    }
    
    // MARK: updateByteAlignment(to:)
    
    private func updateByteAlignment(to byteAlignment: ImageUploadAlignment, updatingUserDefaults: Bool = true) {
        dfuByteAlignment.text = "\(byteAlignment)"
        uploadConfiguration.byteAlignment = byteAlignment
        guard updatingUserDefaults else { return }
        UserDefaults.standard.set(byteAlignment.rawValue, forKey: Key.byteAlignment.rawValue)
    }
    
    // MARK: updateBufferSize(to:)
    
    private func updateBufferSize(to bufferSize: Int, updatingUserDefaults: Bool = true) {
        self.uploadConfiguration.reassemblyBufferSize = UInt64(bufferSize)
        self.dfuChunkSize.text = "\(self.uploadConfiguration.reassemblyBufferSize)"
        guard updatingUserDefaults else { return }
        UserDefaults.standard.set(bufferSize, forKey: Key.chunkSize.rawValue)
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
    
    @IBAction func start(_ sender: UIButton) {
        if let envelope = package?.envelope {
            // SUIT has "no mode" to select
            // (We use modes in the code only, but SUIT has no concept of upload modes)
            startFirmwareUpload(envelope: envelope)
        } else if let package {
            startFirmwareUpload(package: package)
        }
    }
    
    @IBAction func pause(_ sender: UIButton) {
        status.textColor = .secondary
        status.text = "PAUSED"
        actionPause.isHidden = true
        actionResume.isHidden = false
        dfuSpeed.isHidden = true
        imageManager.pauseUpload()
    }
    
    @IBAction func resume(_ sender: UIButton) {
        status.textColor = .secondary
        status.text = "UPLOADING..."
        actionPause.isHidden = false
        actionResume.isHidden = true
        uploadImageSize = nil
        imageManager.continueUpload()
    }
    
    @IBAction func cancel(_ sender: UIButton) {
        actionBuffers.isEnabled = true
        actionAlignment.isEnabled = true
        actionChunks.isEnabled = true
        actionStart.isHidden = false
        actionResume.isHidden = true
        actionPause.isHidden = true
        actionCancel.isHidden = true
        actionSelect.isEnabled = false
        
        status.textColor = .secondary
        status.text = "Cancelled"
        
        uploadImageSize = nil
        uploadTimestamp = nil
        
        progress.progress = .zero
        dfuSpeed.isHidden = true
        imageManager.cancelUpload()
    }
    
    private var package: McuMgrPackage?
    private var imageManager: ImageManager!
    private var defaultManager: DefaultManager!
    var transport: McuMgrTransport! {
        didSet {
            imageManager = ImageManager(transport: transport)
            imageManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            defaultManager = DefaultManager(transport: transport)
            defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    private var initialBytes: Int = 0
    private var uploadConfiguration = FirmwareUpgradeConfiguration(pipelineDepth: 1, byteAlignment: .disabled)
    private var uploadImageSize: Int!
    private var uploadTimestamp: Date!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.translatesAutoresizingMaskIntoConstraints = false
        restoreAdvancedDefaults()
    }
    
    // MARK: - Logic
    
    private func checkBootloader(callback: @escaping (_ bootloader: BootloaderInfoResponse.Bootloader) -> Void) {
        defaultManager.bootloaderInfo(query: .name) { response, error in
            guard error == nil, let response else {
                callback(.mcuboot)
                return
            }
            callback(response.bootloader ?? .mcuboot)
        }
    }
    
    private func startFirmwareUpload(package: McuMgrPackage) {
        uploadImageSize = nil
        let alertController = buildSelectImageController()
        let configuration = uploadConfiguration
        
        checkBootloader { [weak self] bootloader in
            let images: [ImageManager.Image]
            
            switch bootloader {
            case .suit where package.images.count == 1:
                let singleImage: ImageManager.Image! = package.images.first
                let partitions = 0...3
                images = partitions.map {
                    ImageManager.Image(image: $0, hash: singleImage.hash, data: singleImage.data)
                }
            default:
                images = package.images
            }
            
            for image in images {
                alertController.addAction(UIAlertAction(title: image.imageName(), style: .default) { [weak self]
                    action in
                    self?.uploadWillStart()
                    _ = self?.imageManager.upload(images: [image], using: configuration, delegate: self)
                })
            }
            
            self?.present(alertController, animated: true)
        }
    }
    
    private func startFirmwareUpload(envelope: McuMgrSuitEnvelope) {
        // sha256 is the currently only supported mode.
        // The rest are optional to implement in SUIT.
        guard let sha256Hash = envelope.digest.hash(for: .sha256) else {
            uploadDidFail(with: McuMgrSuitParseError.supportedAlgorithmNotFound)
            return
        }
        uploadWillStart()
        let image = ImageManager.Image(image: 0, hash: sha256Hash, data: envelope.data)
        _ = imageManager.upload(images: [image], using: uploadConfiguration, delegate: self)
    }
}

// MARK: - Defaults

fileprivate extension FirmwareUploadViewController {
    
    enum Key: String, RawRepresentable {
        case pipelineDepth = "advanced_PipelineDepth"
        case byteAlignment = "advanced_ByteAlignment"
        case chunkSize = "advanced_ChunkSize"
    }
    
    func restoreAdvancedDefaults() {
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
        
        if UserDefaults.standard.object(forKey: Key.chunkSize.rawValue) != nil {
            let chunkSize = UserDefaults.standard.integer(forKey: Key.chunkSize.rawValue)
            updateBufferSize(to: chunkSize, updatingUserDefaults: false)
        }
    }
}

// MARK: - ImageUploadDelegate

extension FirmwareUploadViewController: ImageUploadDelegate {
    
    func uploadWillStart() {
        actionBuffers.isEnabled = false
        actionAlignment.isEnabled = false
        actionChunks.isEnabled = false
        actionStart.isHidden = true
        actionPause.isHidden = false
        actionCancel.isHidden = false
        actionSelect.isEnabled = false
        
        status.textColor = .secondary
        status.text = "UPLOADING..."
        
        uploadImageSize = nil
        uploadTimestamp = nil
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
        status.text = error.localizedDescription
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
        status.textColor = .secondary
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
        status.textColor = .secondary
        status.text = "UPLOAD COMPLETE"
        package = nil
    }
}

// MARK: - Document Picker

extension FirmwareUploadViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentAt url: URL) {
        self.package = nil
        
        switch parse(url) {
        case .success(let package):
            self.package = package
        case .failure(let error):
            onParseError(error, for: url)
        }
        (parent as? ImageController)?.innerViewReloaded()
    }
    
    // MARK: - Private
    
    func parse(_ url: URL) -> Result<McuMgrPackage, Error> {
        do {
            let package = try McuMgrPackage(from: url)
            fileName.text = url.lastPathComponent
            fileSize.text = package.sizeString()
            fileSize.numberOfLines = 0
            fileHash.text = package.hashString()
            fileHash.numberOfLines = 0
            
            dfuNumberOfBuffers.text = uploadConfiguration.pipelineDepth == 1 ? "Disabled" : "\(uploadConfiguration.pipelineDepth + 1)"
            dfuByteAlignment.text = "\(uploadConfiguration.byteAlignment)"
            dfuChunkSize.text = "\(uploadConfiguration.reassemblyBufferSize)"
            
            status.textColor = .secondary
            status.text = "READY"
            status.numberOfLines = 0
            actionStart.isEnabled = true
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
