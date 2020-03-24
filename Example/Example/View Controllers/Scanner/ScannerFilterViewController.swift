/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit

protocol ScannerFilterDelegate : class {
    /// Called when user modifies the filter.
    func filterSettingsDidChange(filterByUuid: Bool, filterByRssi: Bool)
}

class ScannerFilterViewController: UIViewController {
    
    @IBOutlet weak var filterByUuid: UISwitch!
    @IBOutlet weak var filterByRssi: UISwitch!
    
    var filterByUuidEnabled: Bool!
    var filterByRssiEnabled: Bool!
    weak var delegate: ScannerFilterDelegate?
    
    @IBAction func filterValueChanged(_ sender: UISwitch) {
        filterByUuidEnabled = filterByUuid.isOn
        filterByRssiEnabled = filterByRssi.isOn
        
        delegate?.filterSettingsDidChange(
            filterByUuid: filterByUuidEnabled,
            filterByRssi: filterByRssiEnabled)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        filterByUuid.isOn = filterByUuidEnabled
        filterByRssi.isOn = filterByRssiEnabled
    }
}
