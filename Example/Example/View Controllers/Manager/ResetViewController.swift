/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

// MARK: - ResetViewController

final class ResetViewController: UIViewController, McuMgrViewController {

    // MARK: @IBOutlet
    
    @IBOutlet weak var resetAction: UIButton!
    
    // MARK: @IBAction
    
    @IBAction func reset(_ sender: UIButton) {
        let alertController = UIAlertController(title: "Reset Mode", message: nil, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    
        // If the device is an iPad set the popover presentation controller
        if let presenter = alertController.popoverPresentationController {
            presenter.sourceView = self.view
            presenter.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            presenter.permittedArrowDirections = []
        }
        
        for bootMode in DefaultManager.ResetBootMode.allCases {
            alertController.addAction(UIAlertAction(title: "\(bootMode.description) Mode", style: .default) { [unowned self] action in
                self.callReset(mode: bootMode)
            })
        }
        present(alertController, animated: true)
    }
    
    // MARK: Properties
    
    private var defaultManager: DefaultManager!
    var transport: McuMgrTransport! {
        didSet {
            defaultManager = DefaultManager(transport: transport)
            defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    
    // MARK: callReset(mode:)
    
    private func callReset(mode: DefaultManager.ResetBootMode) {
        resetAction.isEnabled = false
        defaultManager.reset(bootMode: mode) { (response, error) in
            self.resetAction.isEnabled = true
        }
    }
}
