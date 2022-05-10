/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class BaseViewController: UITabBarController {

    var transporter: McuMgrTransport!
    var peripheral: DiscoveredPeripheral! {
        didSet {
            let bleTransporter = McuMgrBleTransport(peripheral.basePeripheral)
            bleTransporter.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            transporter = bleTransporter
        }
    }
    
    override func viewDidLoad() {
        title = peripheral.advertisedName
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        transporter?.close()
    }
}
