/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit

// MARK: - ScannerFilterDelegate

protocol ScannerFilterDelegate: AnyObject {
    /// Called when user modifies the filter.
    func filterSettingsDidChange(filterByName: Bool, filterByRssi: Bool)
}

// MARK: - ScannerFilterViewController

class ScannerFilterViewController: UIViewController {
    
    @IBOutlet weak var filterByName: UISwitch!
    @IBOutlet weak var filterByRssi: UISwitch!
    
    var filterByNameEnabled: Bool!
    var filterByRssiEnabled: Bool!
    weak var delegate: ScannerFilterDelegate?
    
    @IBAction func filterValueChanged(_ sender: UISwitch) {
        filterByNameEnabled = filterByName.isOn
        filterByRssiEnabled = filterByRssi.isOn
        
        delegate?.filterSettingsDidChange(
            filterByName: filterByNameEnabled,
            filterByRssi: filterByRssiEnabled)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        filterByName.isOn = filterByNameEnabled
        filterByRssi.isOn = filterByRssiEnabled
    }
}
