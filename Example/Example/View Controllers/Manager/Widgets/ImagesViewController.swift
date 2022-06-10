/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class ImagesViewController: UIViewController , McuMgrViewController{
    
    @IBOutlet weak var message: UILabel!
    @IBOutlet weak var readAction: UIButton!
    @IBOutlet weak var testAction: UIButton!
    @IBOutlet weak var confirmAction: UIButton!
    @IBOutlet weak var eraseAction: UIButton!
    
    @IBAction func read(_ sender: UIButton) {
        busy()
        defaultManager.params { response, _ in
            self.mcuMgrResponse = response
            self.imageManager.list { (response, error) in
                self.lastResponse = response
                self.handle(response, error)
            }
        }
    }
    
    @IBAction func test(_ sender: UIButton) {
        selectImageCore() { [weak self] imageHash in
            self?.busy()
            self?.imageManager.test(hash: imageHash) { (response, error) in
                self?.lastResponse = response
                self?.handle(response, error)
            }
        }
    }
    @IBAction func confirm(_ sender: UIButton) {
        selectImageCore() { [weak self] imageHash in
            self?.busy()
            self?.imageManager.confirm(hash: imageHash) { (response, error) in
                self?.lastResponse = response
                self?.handle(response, error)
            }
        }
    }
    @IBAction func erase(_ sender: UIButton) {
        busy()
        imageManager.erase { (response, error) in
            if let _ = response {
                self.read(sender)
            } else {
                self.readAction.isEnabled = true
                self.message.textColor = .systemRed
                self.message.text = "\(error!)"
            }
        }
    }
    
    private var mcuMgrResponse: McuMgrParametersResponse?
    private var lastResponse: McuMgrImageStateResponse?
    private var imageManager: ImageManager!
    private var defaultManager: DefaultManager!
    var transporter: McuMgrTransport! {
        didSet {
            imageManager = ImageManager(transporter: transporter)
            imageManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            defaultManager = DefaultManager(transporter: transporter)
            defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    var height: CGFloat = 110
    var tableView: UITableView!
    
    private func selectImageCore(callback: @escaping (([UInt8]) -> Void)) {
        guard let responseImages = lastResponse?.images, responseImages.count > 1 else {
            if let image = lastResponse?.images?.first, !image.confirmed {
                callback(image.hash)
            }
            return
        }
        
        let alertController = UIAlertController(title: "Select Image", message: nil, preferredStyle: .actionSheet)
        for image in responseImages {
            guard !image.confirmed else { continue }
            let title = "Image \(image.image!), Slot \(image.slot!)"
            alertController.addAction(UIAlertAction(title: title, style: .default) { action in
                callback(image.hash)
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
    
    private func handle(_ response: McuMgrImageStateResponse?, _ error: Error?) {
        let bounds = CGSize(width: message.frame.width, height: CGFloat.greatestFiniteMagnitude)
        let oldRect = message.sizeThatFits(bounds)
        
        if let response = response {
            if response.isSuccess(), let images = response.images {
                var info = ""
                
                if let mcuMgrResponse = mcuMgrResponse {
                    info += "McuMgr Parameters:\n"
                    if let bufferCount = mcuMgrResponse.bufferCount,
                       let bufferSize = mcuMgrResponse.bufferSize {
                        info += "• Buffer Count: \(bufferCount)\n"
                        info += "• Buffer Size: \(bufferSize) bytes\n"
                    } else {
                        info += "• Buffer Count: N/A\n"
                        info += "• Buffer Size: N/A\n"
                    }
                }
                
                info += "\nSplit status: \(response.splitStatus ?? 0)\n"
                
                for image in images {
                    info += "\nImage \(image.image!)\n" +
                        "• Slot: \(image.slot!)\n" +
                        "• Version: \(image.version!)\n" +
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
                    if !image.bootable && !image.pending && !image.confirmed && !image.active && !image.permanent {
                        info += "None"
                    } else {
                        info = String(info.dropLast(2))
                    }
                }
                readAction.isEnabled = true
                testAction.isEnabled = images.count > 1 && !images[1].pending
                confirmAction.isEnabled = images.count > 1 && !images[1].permanent
                eraseAction.isEnabled = images.count > 1 && !images[1].confirmed
                
                message.text = info
                message.textColor = .primary
            } else { // not a success
                readAction.isEnabled = true
                message.textColor = .systemRed
                message.text = "Device returned error: \(response.returnCode)"
            }
        } else { // no response
            readAction.isEnabled = true
            message.textColor = .systemRed
            if let error = error {
                message.text = "\(error.localizedDescription)"
            } else {
                message.text = "Empty response"
            }
        }
        let newRect = message.sizeThatFits(bounds)
        let diff = newRect.height - oldRect.height
        height += diff
        tableView.reloadData()
    }
    
    private func busy() {
        readAction.isEnabled = false
        testAction.isEnabled = false
        confirmAction.isEnabled = false
        eraseAction.isEnabled = false
    }
}
