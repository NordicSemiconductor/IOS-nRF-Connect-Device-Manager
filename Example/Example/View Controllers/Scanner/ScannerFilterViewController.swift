/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit

protocol ScannerFilterDelegate {
    /// Called when user modifies the filter.
    func filterSettingsDidChange(filterByUuid: Bool, filterByRssi: Bool)
}

class ScannerFilterViewController: UIViewController {
    
    @IBOutlet weak var filterByUuid: UISwitch!
    @IBOutlet weak var filterByRssi: UISwitch!
    
    var filterByUuidEnabled: Bool!
    var filterByRssiEnabled: Bool!
    var delegate: ScannerFilterDelegate?
    
    @IBAction func filterValueChanged(_ sender: UISwitch) {
        filterByUuidEnabled = self.filterByUuid.isOn
        filterByRssiEnabled = self.filterByRssi.isOn
        
        delegate?.filterSettingsDidChange(filterByUuid: filterByUuidEnabled, filterByRssi: filterByRssiEnabled)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        filterByUuid.isOn = filterByUuidEnabled
        filterByRssi.isOn = filterByRssiEnabled
    }
}
