/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

// MARK: - ImageController

final class ImageController: UITableViewController {
    
    // MARK: @IBOutlet(s)
    
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var mcuMgrParams: UILabel!
    @IBOutlet weak var bootloaderName: UILabel!
    @IBOutlet weak var bootloaderMode: UILabel!
    @IBOutlet weak var bootloaderSlot: UILabel!
    @IBOutlet weak var kernel: UILabel!
    @IBOutlet weak var otaStatusLabel: UILabel!
    @IBOutlet weak var observabilityStatus: UILabel!
    
    // MARK: Private Properties
    
    /// Instance if Images View Controller, required to get its
    /// height when data are obtained and height changes.
    private var imagesViewController: ImagesViewController!
    
    var otaStatus: OTAStatus?
    
    // MARK: UIViewController
    
    override func viewDidAppear(_ animated: Bool) {
        showModeSwitch()
        
        let baseController = parent as? BaseViewController
        baseController?.deviceStatusDelegate = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        tabBarController?.navigationItem.rightBarButtonItem = nil
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let baseController = parent as! BaseViewController
        let transport: McuMgrTransport! = baseController.transport
        
        var destination = segue.destination as? McuMgrViewController
        destination?.transport = transport
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        (parent as? BaseViewController)?.onDeviceStatusAccessoryTapped(at: indexPath)
    }
    
    func innerViewReloaded() {
        tableView.beginUpdates()
        tableView.setNeedsDisplay()
        tableView.endUpdates()
    }
    
    // MARK: Handling Basic / Advanced mode
    
    private var advancedMode: Bool = false
    
    @objc func modeSwitched() {
        showModeSwitch(toggle: true)
        DispatchQueue.main.async { [unowned self] in
            self.tableView.reloadData()
        }
    }
    
    private func showModeSwitch(toggle: Bool = false) {
        if toggle {
            advancedMode.toggle()
        }
        
        let action = advancedMode ? "Basic" : "Advanced"
        let navItem = tabBarController?.navigationItem
        navItem?.rightBarButtonItem = UIBarButtonItem(title: action, style: .plain,
                                                     target: self, action: #selector(modeSwitched))
    }
    
    override func tableView(_ tableView: UITableView,
                            heightForHeaderInSection section: Int) -> CGFloat {
        if (advancedMode && section == 1) || (!advancedMode && 2...5 ~= section) {
            return 0.1
        }
        return super.tableView(tableView, heightForHeaderInSection: section)
    }
    
    override func tableView(_ tableView: UITableView,
                            heightForFooterInSection section: Int) -> CGFloat {
        if (advancedMode && section == 1) || (!advancedMode && 2...5 ~= section) {
            return 0.1
        }
        return super.tableView(tableView, heightForFooterInSection: section)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if (advancedMode && section == 1) || (!advancedMode && 2...5 ~= section) {
            return 0
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if (advancedMode && section == 1) || (!advancedMode && 2...5 ~= section) {
            return nil
        }
        return super.tableView(tableView, titleForHeaderInSection: section)
    }
}

// MARK: - DeviceStatusDelegate

extension ImageController: DeviceStatusManager.Delegate {
    
    func connectionStateDidChange(_ state: PeripheralState) {
        connectionStatus.text = state.description
    }
    
    func statusInfoDidChange(_ info: DeviceStatusInfo) {
        if let buffers = info.bufferCount, let size = info.bufferSize {
            mcuMgrParams.text = "\(buffers) x \(size) bytes"
        }
        if let appInfo = info.appInfoOutput {
            kernel.text = appInfo
        }
        bootloaderName.text = (info.bootloader ?? .unknown).description
        if let mode = info.bootloaderMode {
            bootloaderMode.text = mode.description
        }
        if let slot = info.bootloaderSlot {
            bootloaderSlot.text = "\(slot)"
        }
    }
    
    func otaStatusChanged(_ status: OTAStatus) {
        otaStatusLabel.text = status.description
        otaStatus = status
    }
    
    func observabilityStatusChanged(_ statusInfo: ObservabilityStatusInfo) {
        observabilityStatus.text = statusInfo.status.description
    }
}
