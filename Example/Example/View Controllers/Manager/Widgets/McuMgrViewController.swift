/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

protocol McuMgrViewController {

    var transport: McuMgrTransport! { get set }
    
    func buildSelectImageController() -> UIAlertController
}

extension McuMgrViewController where Self: UIViewController {
    
    // MARK: buildSelectImageController()
    
    func buildSelectImageController() -> UIAlertController {
        let alertController = UIAlertController(title: "Select", message: nil, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    
        // If the device is an iPad set the popover presentation controller
        if let presenter = alertController.popoverPresentationController {
            presenter.sourceView = self.view
            presenter.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            presenter.permittedArrowDirections = []
        }
        
        return alertController
    }
}
