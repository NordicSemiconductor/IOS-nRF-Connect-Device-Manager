/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class ImageController: UITableViewController {
    @IBOutlet weak var connectionStatus: ConnectionStateLabel!
    
    /// Instance if Images View Controller, required to get its
    /// height when data are obtained and height changes.
    private var imagesViewController: ImagesViewController!
    
    override func viewDidAppear(_ animated: Bool) {
        showModeSwitch()
        
        // Set the connection status label as transport delegate.
        let baseController = parent as! BaseViewController
        let bleTransporter = baseController.transporter as? McuMgrBleTransport
        bleTransporter?.delegate = connectionStatus
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        tabBarController!.navigationItem.rightBarButtonItem = nil
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let baseController = parent as! BaseViewController
        let transporter = baseController.transporter!
        
        var destination = segue.destination as? McuMgrViewController
        destination?.transporter = transporter
        
        if let imagesViewController = segue.destination as? ImagesViewController {
            self.imagesViewController = imagesViewController
            imagesViewController.tableView = tableView
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 3 /* Images */ {
            return imagesViewController.height
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    // MARK: - Handling Basic / Advanced mode
    private var advancedMode: Bool = false
    
    @objc func modeSwitched() {
        showModeSwitch(toggle: true)
        tableView.reloadData()
    }
    
    private func showModeSwitch(toggle: Bool = false) {
        if toggle {
            advancedMode = !advancedMode
        }
        let action = advancedMode ? "Basic" : "Advanced"
        let navItem = tabBarController!.navigationItem
        navItem.rightBarButtonItem = UIBarButtonItem(title: action,
                                                     style: .plain,
                                                     target: self,
                                                     action: #selector(modeSwitched))
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
