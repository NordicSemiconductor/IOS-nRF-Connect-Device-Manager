/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

// MARK: - LogsStatsController

final class LogsStatsController: UITableViewController {
    
    // MARK: @IBOutlet(s)
    
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var mcuMgrParams: UILabel!
    @IBOutlet weak var bootloaderName: UILabel!
    @IBOutlet weak var bootloaderMode: UILabel!
    @IBOutlet weak var bootloaderSlot: UILabel!
    @IBOutlet weak var kernel: UILabel!
    @IBOutlet weak var stats: UILabel!
    @IBOutlet weak var refreshAction: UIButton!
    
    // MARK: @IBAction(s)
    
    @IBAction func refreshTapped(_ sender: UIButton) {
        statsManager.list(callback: statsCallback)
    }
    
    // MARK: statsCallback
    
    private lazy var statsCallback: McuMgrCallback<McuMgrStatsListResponse> = { [weak self] response, error in
        guard let self else { return }
        tableView.beginUpdates()
        defer {
            tableView.setNeedsDisplay()
            tableView.endUpdates()
        }
        
        guard let response else {
            stats.textColor = .systemRed
            stats.text = error?.localizedDescription ?? "Unknown Error"
            return
        }
        
        stats.text = ""
        stats.textColor = .primary
        
        if let names = response.names, !names.isEmpty {
            for module in names {
                // Request stats for each module.
                statsManager.read(module: module, callback: { [weak self] (moduleStats, moduleError) in
                    var resultString = "\(module)"
                    
                    if let moduleStats {
                        if let group = moduleStats.group {
                            resultString += " (\(group))"
                        }
                        resultString += ":\n"
                        if let fields = moduleStats.fields {
                            for field in fields {
                                resultString += "• \(field.key): \(field.value)\n"
                            }
                        } else {
                            resultString += "• Empty\n"
                        }
                    } else {
                        resultString += "\(moduleError?.localizedDescription ?? "Unknown Error")\n"
                    }
                    if module != names.last {
                        resultString += "\n"
                    } else {
                        resultString.removeLast()
                    }
                    
                    // And append the received stats to the UILabel.
                    self?.stats.text! += resultString
                })
            }
        } else {
            stats.text = "No stats found"
        }
    }
    
    // MARK: Private Properties
    
    private var statsManager: StatsManager!
    
    // MARK: UIViewController
    
    override func viewDidAppear(_ animated: Bool) {
        guard let baseController = parent as? BaseViewController else { return }
        baseController.deviceStatusDelegate = self
        
        let transport: McuMgrTransport! = baseController.transport
        statsManager = StatsManager(transport: transport)
        statsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
}

// MARK: - DeviceStatusDelegate

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
    
    func bootloaderSlotReceived(_ slot: UInt64) {
        bootloaderSlot.text = "\(slot)"
    }
    
    func appInfoReceived(_ output: String) {
        kernel.text = output
    }
    
    func mcuMgrParamsReceived(buffers: Int, size: Int) {
        mcuMgrParams.text = "\(buffers) x \(size) bytes"
    }
}
