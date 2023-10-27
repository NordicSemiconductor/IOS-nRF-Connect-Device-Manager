/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary
import CoreBluetooth

protocol DeviceStatusDelegate: AnyObject {
    func connectionStateDidChange(_ state: PeripheralState)
    func bootloaderNameReceived(_ name: String)
    func bootloaderModeReceived(_ mode: BootloaderInfoResponse.Mode)
    func appInfoReceived(_ output: String)
    func mcuMgrParamsReceived(buffers: Int, size: Int)
}

class BaseViewController: UITabBarController {
    weak var deviceStatusDelegate: DeviceStatusDelegate? {
        didSet {
            if let state {
                deviceStatusDelegate?.connectionStateDidChange(state)
            }
            if let bootloaderName {
                deviceStatusDelegate?.bootloaderNameReceived(bootloaderName)
            }
            if let bootloaderMode {
                deviceStatusDelegate?.bootloaderModeReceived(bootloaderMode)
            }
            if let appInfoOutput {
                deviceStatusDelegate?.appInfoReceived(appInfoOutput)
            }
            if let mcuMgrParams {
                deviceStatusDelegate?.mcuMgrParamsReceived(buffers: mcuMgrParams.buffers, size: mcuMgrParams.size)
            }
        }
    }
    
    var transporter: McuMgrTransport!
    var peripheral: DiscoveredPeripheral! {
        didSet {
            let bleTransporter = McuMgrBleTransport(peripheral.basePeripheral)
            bleTransporter.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            bleTransporter.delegate = self
            transporter = bleTransporter
        }
    }
    
    private var state: PeripheralState? {
        didSet {
            if let state {
                deviceStatusDelegate?.connectionStateDidChange(state)
            }
        }
    }
    private var bootloaderName: String? {
        didSet {
            if let bootloaderName {
                deviceStatusDelegate?.bootloaderNameReceived(bootloaderName)
            }
        }
    }
    private var bootloaderMode: BootloaderInfoResponse.Mode? {
        didSet {
            if let bootloaderMode {
                deviceStatusDelegate?.bootloaderModeReceived(bootloaderMode)
            }
        }
    }
    private var appInfoOutput: String? {
        didSet {
            if let appInfoOutput {
                deviceStatusDelegate?.appInfoReceived(appInfoOutput)
            }
        }
    }
    private var mcuMgrParams: (buffers: Int, size: Int)? {
        didSet {
            if let mcuMgrParams {
                deviceStatusDelegate?.mcuMgrParamsReceived(buffers: mcuMgrParams.buffers, size: mcuMgrParams.size)
            }
        }
    }
    
    override func viewDidLoad() {
        title = peripheral.advertisedName
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        transporter?.close()
    }
}

extension BaseViewController: PeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        self.state = state
        
        if state == .connected {
            let defaultManager = DefaultManager(transporter: transporter)
            defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            defaultManager.params { [weak self] response, error in
                if let count = response?.bufferCount,
                   let size = response?.bufferSize {
                    self?.mcuMgrParams = (Int(count), Int(size))
                }
                defaultManager.applicationInfo(format: [.kernelName, .kernelVersion]) { [weak self] response, error in
                    self?.appInfoOutput = response?.response
                 
                    defaultManager.bootloaderInfo(query: .name) { [weak self] response, error in
                        self?.bootloaderName = response?.bootloader
                        
                        if response?.bootloader == "MCUboot" {
                            defaultManager.bootloaderInfo(query: .mode) { [weak self] response, error in
                                self?.bootloaderMode = response?.mode
                            }
                        }
                    }
                }
            }
        }
    }
    
}
