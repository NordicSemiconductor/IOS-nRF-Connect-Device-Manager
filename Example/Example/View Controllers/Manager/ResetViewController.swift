/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import McuManager

class ResetViewController: UIViewController, McuMgrViewController {

    @IBOutlet weak var resetAction: UIButton!
    
    @IBAction func reset(_ sender: UIButton) {
        resetAction.isEnabled = false
        defaultManager.reset { (response, error) in
            self.resetAction.isEnabled = true
        }
    }
    
    private var defaultManager: DefaultManager!
    var transporter: McuMgrTransport! {
        didSet {
            defaultManager = DefaultManager(transporter: transporter)
            defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
}
