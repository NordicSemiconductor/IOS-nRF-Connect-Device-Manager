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
    
    @IBOutlet weak var switchToFirmwareLoaderToggle: UISwitch!
    @IBOutlet weak var infoButton: UIButton!
    @IBOutlet weak var advertisingNameTextField: UITextField!
    @IBOutlet weak var resetAction: UIButton!
    
    // MARK: @IBAction
    
    @IBAction func firmwareLoaderToggleChanged(_ sender: UISwitch) {
        advertisingNameTextField.isEnabled = sender.isOn
    }
    
    @IBAction func firmwareLoaderNameEditingDone(_ sender: UITextField) {
        sender.resignFirstResponder()
        callReset(mode: .bootloader)
    }
    
    @IBAction func firmwareLoaderNameEditingEnded(_ sender: UITextField) {
        sender.resignFirstResponder()
    }
    
    @IBAction func reset(_ sender: UIButton) {
        let mode: DefaultManager.ResetBootMode = switchToFirmwareLoaderToggle.isOn
            ? .bootloader : .normal
        callReset(mode: mode)
    }
    
    // MARK: Properties
    
    private var defaultManager: DefaultManager!
    private var settingsManager: SettingsManager!
    
    var transport: McuMgrTransport! {
        didSet {
            defaultManager = DefaultManager(transport: transport)
            defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            
            settingsManager = SettingsManager(transport: transport)
            settingsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    
    // MARK: viewDidLoad
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.translatesAutoresizingMaskIntoConstraints = false
        firmwareLoaderToggleChanged(switchToFirmwareLoaderToggle)
        
        advertisingNameTextField.placeholder = "Defaults to 'fl_[HH]_[mm]'"
    }
    
    // MARK: callReset(mode:)
    
    private func callReset(mode: DefaultManager.ResetBootMode) {
        resetAction.isEnabled = false
        guard mode == .bootloader else {
            defaultManager.reset(bootMode: mode) { [unowned self] (response, error) in
                resetAction.isEnabled = true
            }
            return
        }
        
        let name: String! = (advertisingNameTextField.text?.hasItems ?? false) ?
            advertisingNameTextField.text : settingsManager.generateNewAdvertisingName()
        settingsManager.setFirmwareLoaderAdvertisingName(name) { [unowned self] response, error in
            guard error == nil else {
                resetAction.isEnabled = true
                return
            }
            
            defaultManager.reset(bootMode: mode) { [unowned self] (response, error) in
                resetAction.isEnabled = true
            }
        }
    }
}
