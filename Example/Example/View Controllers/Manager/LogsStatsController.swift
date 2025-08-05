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
        defer {
            onStatsChanged()
        }
        
        guard let response else {
            stats.textColor = .systemRed
            stats.text = error?.localizedDescription ?? "Unknown Error"
            return
        }
        
        stats.text = ""
        stats.textColor = .primary
        
        guard let modules = response.names, !modules.isEmpty else {
            stats.text = "No stats found"
            return
        }
        
        for module in modules {
            statsManager.read(module: module, callback: { [unowned self] (moduleStats, moduleError) in
                self.stats.text! += self.moduleStatsString(module, stats: moduleStats, error: moduleError)
                self.onStatsChanged()
            })
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

// MARK: - Private

private extension LogsStatsController {
    
    func moduleStatsString(_ module: String, stats: McuMgrStatsResponse?, error: (any Error)?) -> String {
        var resultString = "\(module)"
        if let stats {
            if let group = stats.group {
                resultString += " (\(group))"
            }
            resultString += ":\n"
            if let fields = stats.fields {
                for field in fields {
                    resultString += "• \(field.key): \(field.value)\n"
                }
            } else {
                resultString += "• Empty\n"
            }
        } else {
            resultString += "\(error?.localizedDescription ?? "Unknown Error")\n"
        }
        
        resultString += "\n"
        return resultString
    }
    
    func onStatsChanged() {
        tableView.beginUpdates()
        tableView.setNeedsDisplay()
        tableView.endUpdates()
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
