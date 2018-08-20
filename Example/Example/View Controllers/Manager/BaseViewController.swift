/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import McuManager

class BaseViewController: UITabBarController {

    var transporter: McuMgrTransport!
    var peripheral: DiscoveredPeripheral! {
        didSet {
            transporter = McuMgrBleTransport(peripheral.basePeripheral)
        }
    }
    
    override func viewDidLoad() {
        title = peripheral.advertisedName
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        transporter!.close()
    }
}
