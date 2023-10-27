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
    
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var mcuMgrParams: UILabel!
    @IBOutlet weak var bootloaderName: UILabel!
    @IBOutlet weak var bootloaderMode: UILabel!
    @IBOutlet weak var kernel: UILabel!
    
    var fileDownloadViewController: FileDownloadViewController!
    
    override func viewDidAppear(_ animated: Bool) {
        showPartitionControl()
        
        let baseController = parent as? BaseViewController
        baseController?.deviceStatusDelegate = self
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        tabBarController!.navigationItem.rightBarButtonItem = nil
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let baseController = parent as! BaseViewController
        let transporter = baseController.transporter!
        
        var destination = segue.destination as? McuMgrViewController
        destination?.transporter = transporter
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func innerViewReloaded() {
        tableView.beginUpdates()
        tableView.setNeedsDisplay()
        tableView.endUpdates()
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
                                      message: "Specify the mount point,\ne.g. \"lfs1\" or \"nffs\":",
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

extension FilesController: DeviceStatusDelegate {
    
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
