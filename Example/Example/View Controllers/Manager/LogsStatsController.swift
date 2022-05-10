/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class LogsStatsController: UITableViewController {
    @IBOutlet weak var connectionStatus: ConnectionStateLabel!
    @IBOutlet weak var stats: UILabel!
    @IBOutlet weak var refreshAction: UIButton!
    
    @IBAction func refreshTapped(_ sender: UIButton) {
        statsManager.list { (response, error) in
            let bounds = CGSize(width: self.stats.frame.width, height: CGFloat.greatestFiniteMagnitude)
            var oldRect = self.stats.sizeThatFits(bounds)
            
            if let response = response {
                self.stats.text = ""
                self.stats.textColor = .primary
                
                // Iterate all module names.
                if let names = response.names, !names.isEmpty {
                    names.forEach { module in
                        // Request stats for each module.
                        self.statsManager.read(module: module, callback: { (stats, error2) in
                            // And append the received stats to the UILabel.
                            self.stats.text! += "\(module)"
                            if let stats = stats {
                                if let group = stats.group {
                                    self.stats.text! += " (\(group))"
                                }
                                self.stats.text! += ":\n"
                                if let fields = stats.fields {
                                    for field in fields {
                                        self.stats.text! += "• \(field.key): \(field.value)\n"
                                    }
                                } else {
                                    self.stats.text! += "• Empty\n"
                                }
                            } else {
                                self.stats.text! += "\(error2!)\n"
                            }
                            if module != names.last {
                                self.stats.text! += "\n"
                            } else {
                                self.stats.text!.removeLast()
                            }
                            
                            let newRect = self.stats.sizeThatFits(bounds)
                            let diff = newRect.height - oldRect.height
                            oldRect = newRect
                            self.height += diff
                            self.tableView.reloadData()
                        })
                    }
                } else {
                    self.stats.text = "No stats found."
                }
            } else {
                self.stats.textColor = .systemRed
                self.stats.text = "\(error!)"
                
                let newRect = self.stats.sizeThatFits(bounds)
                let diff = newRect.height - oldRect.height
                self.height += diff
                self.tableView.reloadData()
            }
        }
    }
    
    private var statsManager: StatsManager!
    private var height: CGFloat = 106
    
    override func viewDidLoad() {
        let baseController = parent as! BaseViewController
        let transporter = baseController.transporter!
        statsManager = StatsManager(transporter: transporter)
        statsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // Set the connection status label as transport delegate.
        let bleTransporter = statsManager.transporter as? McuMgrBleTransport
        bleTransporter?.delegate = connectionStatus
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 1 /* Stats */ {
            return height
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }

}
