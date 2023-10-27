/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class LogsStatsController: UITableViewController {
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var mcuMgrParams: UILabel!
    @IBOutlet weak var bootloaderName: UILabel!
    @IBOutlet weak var bootloaderMode: UILabel!
    @IBOutlet weak var kernel: UILabel!
    @IBOutlet weak var stats: UILabel!
    @IBOutlet weak var refreshAction: UIButton!
    
    @IBAction func refreshTapped(_ sender: UIButton) {
        statsManager.list { (response, error) in
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
                        })
                    }
                } else {
                    self.stats.text = "No stats found"
                }
            } else {
                self.stats.textColor = .systemRed
                self.stats.text = error!.localizedDescription
            }
            self.tableView.beginUpdates()
            self.tableView.setNeedsDisplay()
            self.tableView.endUpdates()
        }
    }
    
    private var statsManager: StatsManager!
    
    override func viewDidLoad() {
        let baseController = parent as! BaseViewController
        let transporter = baseController.transporter!
        statsManager = StatsManager(transporter: transporter)
        statsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
    }
    
    override func viewDidAppear(_ animated: Bool) {
        let baseController = parent as? BaseViewController
        baseController?.deviceStatusDelegate = self
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

}

extension LogsStatsController: DeviceStatusDelegate {
    
    func connectionStateDidChange(_ state: PeripheralState) {
        connectionStatus.text = state.description
    }
    
    func bootloaderNameReceived(_ name: String) {
        bootloaderName.text = name
    }
    
    func bootloaderModeReceived(_ mode: BootloaderInfoResponse.Mode) {
        bootloaderMode.text = mode.description
    }
    
    func appInfoReceived(_ output: String) {
        kernel.text = output
    }
    
    func mcuMgrParamsReceived(buffers: Int, size: Int) {
        mcuMgrParams.text = "\(buffers) x \(size) bytes"
    }
    
}
