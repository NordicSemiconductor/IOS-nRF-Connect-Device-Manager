/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class SettingsViewController: UIViewController, McuMgrViewController {

    @IBOutlet weak var factoryResetButton: UIButton!
    
    @IBAction func factoryReset(_ sender: UIButton) {
        busy()
        basicManager.eraseAppSettings { response, error in
            // TODO: Handle error?
            self.done()
        }
    }
    
    private var basicManager: BasicManager!
    var transporter: McuMgrTransport! {
        didSet {
            basicManager = BasicManager(transporter: transporter)
            basicManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    
    private func busy() {
        factoryResetButton.isEnabled = false
    }
    
    private func done() {
        factoryResetButton.isEnabled = true
    }

}
