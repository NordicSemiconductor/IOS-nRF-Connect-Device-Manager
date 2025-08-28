/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary
import ObjectiveC

class ImageController: UITableViewController {
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var mcuMgrParams: UILabel!
    @IBOutlet weak var bootloaderName: UILabel!
    @IBOutlet weak var bootloaderMode: UILabel!
    @IBOutlet weak var bootloaderSlot: UILabel!
    @IBOutlet weak var kernel: UILabel!
    
    // Track if we're currently checking for updates
    var isCheckingForUpdate: Bool {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.isCheckingForUpdate) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.isCheckingForUpdate, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private struct AssociatedKeys {
        static var isCheckingForUpdate = "isCheckingForUpdate"
    }
    
    // MARK: - nRF Cloud OTA IBOutlets
    @IBOutlet weak var nrfCloudStatusLabel: UILabel!
    @IBOutlet weak var checkForUpdatesButton: UIButton!
    @IBOutlet weak var updateInfoCell: UITableViewCell!
    @IBOutlet weak var updateVersionLabel: UILabel!
    @IBOutlet weak var updateSizeLabel: UILabel!
    @IBOutlet weak var updateDescriptionLabel: UILabel!
    @IBOutlet weak var actionButtonsCell: UITableViewCell!
    @IBOutlet weak var downloadInstallButton: UIButton!
    /// Instance if Images View Controller, required to get its
    /// height when data are obtained and height changes.
    private var imagesViewController: ImagesViewController!
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showModeSwitch()
        
        let baseController = parent as? BaseViewController
        baseController?.deviceStatusDelegate = self
        
        // Setup nRF Cloud OTA section if outlets are connected
        if nrfCloudStatusLabel != nil {
            setupNRFCloudOTA()
        }
        
        // Force immediate hiding of update rows
        updateInfoCell?.isHidden = true
        actionButtonsCell?.isHidden = true
        
        // Force reload to apply height changes
        tableView.reloadData()
    }
    
    // MARK: - NRF Cloud OTA
    // Main implementation is in ImageController+NRFCloud.swift extension
    
    func updateNRFCloudStatus(_ status: String) {
        nrfCloudStatusLabel?.text = status
        
        // Update text color based on status
        if status.contains("Ready") {
            nrfCloudStatusLabel?.textColor = .nordicGreen
        } else if status.contains("not available") || status.contains("Error") || status.contains("Failed") || status.contains("401") || status.contains("403") {
            nrfCloudStatusLabel?.textColor = .nordicRed
        } else if status.contains("Connecting") {
            nrfCloudStatusLabel?.textColor = .systemOrange
        } else {
            // Default grey for neutral states like "Not connected"
            if #available(iOS 13.0, *) {
                nrfCloudStatusLabel?.textColor = .secondaryLabel
            } else {
                nrfCloudStatusLabel?.textColor = .gray
            }
        }
    }
    
    func hideUpdateRows() {
        // Mark cells as hidden
        updateInfoCell?.isHidden = true
        actionButtonsCell?.isHidden = true
        
        // Force complete table reload to recalculate heights
        tableView.reloadData()
    }
    
    func getNRFCloudOTASection() -> Int? {
        // Find the section containing NRF Cloud OTA
        // This should be section 6 based on storyboard, but let's verify
        for section in 0..<tableView.numberOfSections {
            if let header = tableView.headerView(forSection: section),
               let label = header.textLabel,
               label.text?.contains("NRF CLOUD") == true {
                return section
            }
        }
        return 6 // Default fallback
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
        // For NRF CLOUD OTA section, check if cells should be hidden
        if indexPath.section == 6 {
            if indexPath.row == 2 && (updateInfoCell?.isHidden ?? true) {
                return 0.0
            }
            if indexPath.row == 3 && (actionButtonsCell?.isHidden ?? true) {
                return 0.0
            }
        }
        
        // For all other cells, use default height
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // Match actual height to prevent caching issues
        return self.tableView(tableView, heightForRowAt: indexPath)
    }
    
    func innerViewReloaded() {
        tableView.beginUpdates()
        tableView.setNeedsDisplay()
        tableView.endUpdates()
        
        // Ensure table view can scroll to show all content
        DispatchQueue.main.async { [weak self] in
            self?.tableView.scrollToRow(at: IndexPath(row: 0, section: 1), at: .top, animated: false)
        }
    }
    
    // MARK: - Handling Basic / Advanced mode
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
        // Don't modify numberOfRowsInSection for static cells - let storyboard handle it
        return super.tableView(tableView, numberOfRowsInSection: section)
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if (advancedMode && section == 1) || (!advancedMode && 2...5 ~= section) {
            return nil
        }
        return super.tableView(tableView, titleForHeaderInSection: section)
    }
}

extension ImageController: DeviceStatusDelegate {
    
    func connectionStateDidChange(_ state: PeripheralState) {
        connectionStatus.text = state.description
        
        // Update NRF Cloud OTA status based on connection
        switch state {
        case .connected:
            // Wait a bit for services to be discovered
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.checkConnectionAndServices()
            }
        case .disconnected:
            updateNRFCloudStatus("Not connected - tap to connect")
            // Only enable button if we're not checking for updates
            if !isCheckingForUpdate {
                checkForUpdatesButton?.isEnabled = true  // Allow clicking to trigger connection
            }
            hideUpdateRows()
        case .connecting:
            updateNRFCloudStatus("Connecting...")
            checkForUpdatesButton?.isEnabled = false
            hideUpdateRows()
        default:
            break
        }
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
