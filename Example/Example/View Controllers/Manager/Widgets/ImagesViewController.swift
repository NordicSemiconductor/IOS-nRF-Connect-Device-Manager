/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class ImagesViewController: UIViewController, McuMgrViewController {
    
    @IBOutlet weak var message: UILabel!
    @IBOutlet weak var readAction: UIButton!
    @IBOutlet weak var testAction: UIButton!
    @IBOutlet weak var confirmAction: UIButton!
    @IBOutlet weak var eraseAction: UIButton!
    
    // MARK: read(sender:)
    
    @IBAction func read(_ sender: UIButton) {
        busy()
        requestBootloaderIfNecessary(sender: sender) { [weak self] sender, bootloader in
            switch bootloader {
            case .suit:
                self?.suitManager.listManifest { [weak self] response, error in
                    self?.suitListResponse = response
                    self?.handle(suitListResponse: response, error)
                }
            case .mcuboot, .unknown:
                self?.imageManager.list { [weak self] response, error in
                    self?.lastResponse = response
                    self?.handle(response, error)
                }
            }
        }
    }
    
    // MARK: test(sender:)
    
    @IBAction func test(_ sender: UIButton) {
        selectImageCore() { [weak self] imageHash in
            self?.busy()
            self?.imageManager.test(hash: imageHash) { [weak self] response, error in
                self?.lastResponse = response
                self?.handle(response, error)
            }
        }
    }
    
    // MARK: confirm(sender:)
    
    @IBAction func confirm(_ sender: UIButton) {
        requestBootloaderIfNecessary(sender: sender) { [weak self] sender, bootloader in
            switch bootloader {
            case .suit:
                self?.busy()
                self?.suitManager.processRecentlyUploadedEnvelope { [weak self] response, error in
                    switch response?.result {
                    case .success:
                        self?.updateUI(text: "Success!", color: .primary, readEnabled: true)
                    case .failure(let error):
                        self?.updateUI(text: error.localizedDescription,
                                       color: .systemRed, readEnabled: true)
                    case .none:
                        self?.updateUI(text: "Unknown Error",
                                       color: .systemRed, readEnabled: true)
                    }
                }
            case .mcuboot, .unknown:
                self?.selectImageCore() { [weak self] imageHash in
                    self?.busy()
                    self?.imageManager.confirm(hash: imageHash) { [weak self] response, error in
                        self?.lastResponse = response
                        self?.handle(response, error)
                    }
                }
            }
        }
    }
    
    // MARK: erase(sender:)
    
    @IBAction func erase(_ sender: UIButton) {
        busy()
        requestBootloaderIfNecessary(sender: sender) { [weak self] sender, bootloader in
            switch bootloader {
            case .suit:
                self?.suitManager.cleanup { [weak self] response, error in
                    if let error {
                        self?.updateUI(text: error.localizedDescription, color: .systemRed, readEnabled: true)
                    } else {
                        if let rc = response?.rc, rc != .ok {
                            self?.updateUI(text: rc.description, color: .systemRed, readEnabled: true)
                        } else {
                            self?.updateUI(text: "Cleanup Successful", color: .primary, readEnabled: true)
                        }
                    }
                }
            case .mcuboot, .unknown:
                self?.imageManager.erase { [weak self] response, error in
                    if let _ = response {
                        self?.read(sender)
                    } else {
                        self?.updateUI(text: error?.localizedDescription ?? "", color: .systemRed, readEnabled: true)
                    }
                }
            }
        }
    }
    
    // MARK: Properties
    
    private var defaultManager: DefaultManager!
    private var bootloader: BootloaderInfoResponse.Bootloader?
    
    private var suitManager: SuitManager!
    private var suitListResponse: SuitListResponse?
    
    private var imageManager: ImageManager!
    private var lastResponse: McuMgrImageStateResponse?
    
    var transport: McuMgrTransport! {
        didSet {
            suitManager = SuitManager(transport: transport)
            suitManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            imageManager = ImageManager(transport: transport)
            imageManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            defaultManager = DefaultManager(transport: transport)
            defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    
    // MARK: requestBootloaderIfNecessary(sender:callback:)
    
    private func requestBootloaderIfNecessary(sender: UIButton, callback: @escaping ((_ sender: UIButton, _ bootloader: BootloaderInfoResponse.Bootloader) -> Void)) {
        guard let bootloader else {
            defaultManager.bootloaderInfo(query: .name) { [weak self] response, error in
                guard let self else { return }
                guard error == nil, let response else {
                    self.bootloader = .mcuboot
                    return
                }
                self.bootloader = response.bootloader ?? .mcuboot
                callback(sender, response.bootloader ?? .mcuboot)
            }
            return
        }
        callback(sender, bootloader)
    }
    
    // MARK: selectImageCore(callback:)
    
    private func selectImageCore(callback: @escaping (([UInt8]) -> Void)) {
        guard let responseImages = lastResponse?.images, responseImages.count > 1 else {
            if let image = lastResponse?.images?.first, !image.confirmed {
                callback(image.hash)
            }
            return
        }
        
        let alertController = buildSelectImageController()
        for image in responseImages {
            guard !image.confirmed else { continue }
            let title = "Image \(image.image), slot \(image.slot)"
            alertController.addAction(UIAlertAction(title: title, style: .default) { action in
                callback(image.hash)
            })
        }
    
        present(alertController, animated: true)
    }
    
    // MARK: viewDidLoad()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.translatesAutoresizingMaskIntoConstraints = false
    }
    
    // MARK: handle(suitListResponse:error:)
    
    private func handle(suitListResponse response: SuitListResponse?, _ error: Error?) {
        if let response {
            switch response.result {
            case .success:
                testAction.isEnabled = false
                confirmAction.isEnabled = true
                eraseAction.isEnabled = true
                updateUI(text: getInfo(from: response), color: .primary, readEnabled: true)
            case .failure(let error):
                updateUI(text: error.localizedDescription,
                         color: .systemRed, readEnabled: true)
            }
        } else {
            readAction.isEnabled = true
            message.textColor = .systemRed
            if let error {
                message.text = error.localizedDescription
            } else {
                message.text = "Empty Response"
            }
        }
        (parent as? ImageController)?.innerViewReloaded()
    }
    
    // MARK: handle(response:error:)
    
    private func handle(_ response: McuMgrImageStateResponse?, _ error: Error?) {
        if let response {
            switch response.result {
            case .success:
                let images = response.images ?? []
                let nonActive = images.count > 1 ? (images[0].active ? 1 : 0) : 0
                testAction.isEnabled = images.count > 1 && !images[nonActive].pending
                confirmAction.isEnabled = images.count > 1 && !images[nonActive].permanent
                eraseAction.isEnabled = images.count > 1 && !images[nonActive].confirmed
                
                updateUI(text: getInfo(from: response), color: .primary, readEnabled: true)
            case .failure(let error):
                updateUI(text: error.localizedDescription,
                         color: .systemRed, readEnabled: true)
            }
        } else { // no response
            readAction.isEnabled = true
            message.textColor = .systemRed
            if let error = error {
                message.text = error.localizedDescription
            } else {
                message.text = "Empty response"
            }
        }
        (parent as? ImageController)?.innerViewReloaded()
    }
    
    // MARK: getInfo()
    
    private func getInfo(from response: SuitListResponse) -> String {
        let roles = response.roles ?? []
        let states = response.states ?? []
        assert(roles.count == states.count)
        
        var info = ""
        for (role, state) in zip(roles, states) {
            let classString = (try? state.classUUID()?.uuidString) ?? "N/A"
            let vendorString = (try? state.vendorUUID()?.uuidString) ?? "N/A"
            let digestString = Data(state.digest ?? []).hexEncodedString(options: [.prepend0x, .upperCase])
            info += "• Role: \(role.description)\n  Sequence Number: \(state.sequenceNumberHexString() ?? "N/A")\n  Class: \(classString)\n  Vendor: \(vendorString)\n  Downgrade Policy: \(state.downgradePreventionPolicy?.description ?? "N/A")\n  Independent Update Policy: \(state.independentUpdateabilityPolicy?.description ?? "N/A")\n  Signature Verification: \(state.signatureCheck?.description ?? "N/A")\n  Verification Policy: \(state.signatureVerificationPolicy?.description ?? "N/A")\n  Digest: \(digestString)\n  Digest Algorithm: \(state.digestAlgorithm?.description ?? "N/A")\n  Version: \(state.semanticVersionString() ?? "N/A")\n\n"
        }
        return info
    }
    
    private func getInfo(from response: McuMgrImageStateResponse) -> String {
        let images = response.images ?? []
        var info = "Split status: \(response.splitStatus ?? 0)"
        
        for image in images {
            info += "\n\nImage: \(image.image), Slot: \(image.slot)\n" +
                "• Version: \(image.version ?? "Unknown")\n" +
                "• Hash: \(Data(image.hash).hexEncodedString(options: .upperCase))\n" +
                "• Flags: "
            if image.bootable {
                info += "Bootable, "
            }
            if image.pending {
                info += "Pending, "
            }
            if image.confirmed {
                info += "Confirmed, "
            }
            if image.active {
                info += "Active, "
            }
            if image.permanent {
                info += "Permanent, "
            }
            if image.compressed {
                info += "Compressed, "
            }
            if !image.bootable && !image.pending && !image.confirmed && !image.active && !image.permanent && !image.compressed {
                info += "None, "
            } else {
                info = String(info.dropLast(2))
            }
        }
        return info
    }
    
    // MARK: updateUI(text:color:readEnabled)
    
    private func updateUI(text: String, color: UIColor, readEnabled: Bool) {
        message.text = text
        message.textColor = color
        readAction.isEnabled = readEnabled
        (parent as? ImageController)?.innerViewReloaded()
    }
    
    // MARK: busy()
    
    private func busy() {
        readAction.isEnabled = false
        testAction.isEnabled = false
        confirmAction.isEnabled = false
        eraseAction.isEnabled = false
    }
}
