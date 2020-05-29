/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import McuManager

class ImagesViewController: UIViewController , McuMgrViewController{
    
    @IBOutlet weak var message: UILabel!
    @IBOutlet weak var readAction: UIButton!
    @IBOutlet weak var testAction: UIButton!
    @IBOutlet weak var confirmAction: UIButton!
    @IBOutlet weak var eraseAction: UIButton!
    
    @IBAction func read(_ sender: UIButton) {
        busy()
        imageManager.list { (response, error) in
            self.handle(response, error)
        }
    }
    @IBAction func test(_ sender: UIButton) {
        busy()
        imageManager.test(hash: imageHash!) { (response, error) in
            self.handle(response, error)
        }
    }
    @IBAction func confirm(_ sender: UIButton) {
        busy()
        imageManager.confirm(hash: imageHash!) { (response, error) in
            self.handle(response, error)
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
    
    private var imageHash: [UInt8]?
    private var imageManager: ImageManager!
    var transporter: McuMgrTransport! {
        didSet {
            imageManager = ImageManager(transporter: transporter)
            imageManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    var height: CGFloat = 110
    var tableView: UITableView!
    
    private func handle(_ response: McuMgrImageStateResponse?, _ error: Error?) {
        let bounds = CGSize(width: message.frame.width, height: CGFloat.greatestFiniteMagnitude)
        let oldRect = message.sizeThatFits(bounds)
        
        if let response = response {
            if response.isSuccess(), let images = response.images {
                var info = "Split status: \(response.splitStatus ?? 0)"
                
                for (i, image) in images.enumerated() {
                    info += "\nSlot \(i)\n" +
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
                    
                    if !image.confirmed {
                        imageHash = image.hash
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
