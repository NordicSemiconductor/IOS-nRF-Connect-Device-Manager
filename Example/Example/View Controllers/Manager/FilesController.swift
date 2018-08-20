/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import McuManager

class FilesController: UITableViewController {
    @IBOutlet weak var connectionStatus: ConnectionStateLabel!
    
    var fileDownloadViewController: FileDownloadViewController!
    
    override func viewDidAppear(_ animated: Bool) {
        // Set the connection status label as transport delegate.
        let baseController = parent as! BaseViewController
        let bleTransporter = baseController.transporter as? McuMgrBleTransport
        bleTransporter?.delegate = connectionStatus
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

}
