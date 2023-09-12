/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class FilesController: UITableViewController {
    static let partitionKey = "partition"
    /**
    [LittleFS GitHub Project](https://github.com/ARMmbed/littlefs)
     */
    static let defaultPartition = "lfs1"
    
    @IBOutlet weak var connectionStatus: ConnectionStateLabel!
    
    var fileDownloadViewController: FileDownloadViewController!
    
    override func viewDidAppear(_ animated: Bool) {
        showPartitionControl()
        
        // Set the connection status label as transport delegate.
        let baseController = parent as! BaseViewController
        let bleTransporter = baseController.transporter as? McuMgrBleTransport
        bleTransporter?.delegate = connectionStatus
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        tabBarController!.navigationItem.rightBarButtonItem = nil
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let baseController = parent as! BaseViewController
        let transporter = baseController.transporter!
        
        var destination = segue.destination as? McuMgrViewController
        destination?.transporter = transporter
        
        if let controller = destination as? FileDownloadViewController {
            fileDownloadViewController = controller
            fileDownloadViewController.tableView = tableView
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 2 /* Download */ {
            return fileDownloadViewController.height
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    // MARK: Partition settings
    private func showPartitionControl() {
        let navItem = tabBarController!.navigationItem
        navItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit,
                                                     target: self,
                                                     action: #selector(presentPartitionSettings))
    }
    
    @objc func presentPartitionSettings() {
        let alert = UIAlertController(title: "Settings",
                                      message: "Specify the mount point,\ne.g. \"lfs\" or \"nffs\":",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Partition"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.returnKeyType = .done
            field.clearButtonMode = .always
            field.text = UserDefaults.standard
                .string(forKey: FilesController.partitionKey)
                ?? FilesController.defaultPartition
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            let newName = alert.textFields![0].text
            if let newName = newName, !newName.isEmpty {
                UserDefaults.standard.set(alert.textFields![0].text,
                                          forKey: FilesController.partitionKey)
                self.tableView.reloadData()
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Default (\(FilesController.defaultPartition))",
                                      style: .default) { _ in
            UserDefaults.standard.set(FilesController.defaultPartition,
                                      forKey: FilesController.partitionKey)
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
