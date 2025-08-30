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
    
    // MARK: - Memfault OTA Properties
    
    // Track if we're currently checking for updates
    var isCheckingForUpdate = false
    
    // Store the current update info
    var currentMemfaultUpdateInfo: NRFCloudOTAManager.UpdateInfo?
    
    // Store active DFU manager and delegate
    var activeDfuManager: FirmwareUpgradeManager?
    var activeDfuDelegate: SimpleDFUDelegate?
    
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
        
        setupNRFCloudOTA()
        
        // Ensure update rows are properly hidden initially
        hideUpdateRows()
    }
    
    // MARK: - NRF Cloud OTA
    // Main implementation is in ImageController+NRFCloud.swift extension
    
    func updateNRFCloudStatus(_ status: String) {
        nrfCloudStatusLabel?.text = status
    }
    
    func hideUpdateRows() {
        // Mark cells as hidden
        updateInfoCell?.isHidden = true
        actionButtonsCell?.isHidden = true
        
        // Just reload the whole table
        tableView.reloadData()
    }
    
    func getNRFCloudOTASection() -> Int? {
        // NRF CLOUD is always section 6
        return 6
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
        // The update cells are actually in section 1 (IMAGE UPGRADE), not section 6
        // Section 1 has 4 rows: container, button, updateInfoCell, actionButtonsCell
        if !advancedMode && indexPath.section == 1 {
            // Hide update info cell (row 2)
            if indexPath.row == 2 {
                let shouldHide = updateInfoCell?.isHidden ?? true
                if shouldHide {
                    return 0.0
                }
            }
            // Hide action buttons cell (row 3)
            if indexPath.row == 3 {
                let shouldHide = actionButtonsCell?.isHidden ?? true
                if shouldHide {
                    return 0.0
                }
            }
        }
        
        // For sections hidden in basic/advanced mode
        if (advancedMode && indexPath.section == 1) || (!advancedMode && 2...5 ~= indexPath.section) {
            return 0.0
        }
        
        // For all other cells, use default height
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // Don't provide estimated heights - let the actual heights be used
        // This prevents caching issues
        return 0
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
        
        // Update cells are in section 1, check footer there too
        if section == 1 && !advancedMode {
            // Check if update cells in section 1 are hidden
            let updateCellsHidden = (updateInfoCell?.isHidden ?? true) && (actionButtonsCell?.isHidden ?? true)
            if updateCellsHidden {
                // Reduce footer to minimize gray space
                return 0.1
            }
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
