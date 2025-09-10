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
    @IBOutlet weak var nRFCloudStatus: UILabel!
    @IBOutlet weak var observabilityStatus: UILabel!
    
    // MARK: Private Properties
    
    /// Instance if Images View Controller, required to get its
    /// height when data are obtained and height changes.
    private var imagesViewController: ImagesViewController!
    
    var cloudStatus: nRFCloudStatus?
    
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

extension ImageController: DeviceStatusDelegate {
    
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
    
    func nRFCloudStatusChanged(_ status: nRFCloudStatus) {
        cloudStatus = status
        switch status {
        case .unavailable:
            nRFCloudStatus.text = "UNAVAILABLE"
        case .missingProjectKey:
            nRFCloudStatus.text = "MISSING PROJECT KEY"
        case .available:
            nRFCloudStatus.text = "READY"
        }
    }
    
    func observabilityStatusChanged(_ status: ObservabilityStatus, pendingCount: Int, pendingBytes: Int, uploadedCount: Int, uploadedBytes: Int) {
        switch status {
        case .receivedEvent(let event):
            switch event {
            case .connected:
                observabilityStatus.text = "CONNECTED"
            case .disconnected:
                observabilityStatus.text = "DISCONNECTED"
            case .notifications:
                observabilityStatus.text = "NOTIFYING"
            case .streaming(let isTrue):
                observabilityStatus.text = isTrue ? "STREAMING" : "NOT STREAMING"
            case .authenticated:
                observabilityStatus.text = "AUTHENTICATED"
            case .updatedChunk:
                observabilityStatus.text = "STREAMING"
            }
        case .connectionClosed:
            observabilityStatus.text = "CLOSED"
        case .unavailable, .errorEvent:
            observabilityStatus.text = "ERROR"
        }
    }
}
