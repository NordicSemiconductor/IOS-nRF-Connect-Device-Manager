/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary
import CoreBluetooth

// MARK: - DeviceStatusDelegate

protocol DeviceStatusDelegate: AnyObject {
    func connectionStateDidChange(_ state: PeripheralState)
    func bootloaderNameReceived(_ name: String)
    func bootloaderModeReceived(_ mode: BootloaderInfoResponse.Mode)
    func appInfoReceived(_ output: String)
    func mcuMgrParamsReceived(buffers: Int, size: Int)
}

// MARK: - BaseViewController

final class BaseViewController: UITabBarController {
    weak var deviceStatusDelegate: DeviceStatusDelegate? {
        didSet {
            if let state {
                deviceStatusDelegate?.connectionStateDidChange(state)
            }
            if let bootloader {
                deviceStatusDelegate?.bootloaderNameReceived(bootloader.description)
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
    
    var transport: McuMgrTransport!
    var peripheral: DiscoveredPeripheral! {
        didSet {
            let bleTransport = McuMgrBleTransport(peripheral.basePeripheral)
            bleTransport.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            bleTransport.delegate = self
            transport = bleTransport
        }
    }
    
    private var state: PeripheralState? {
        didSet {
            if let state {
                deviceStatusDelegate?.connectionStateDidChange(state)
            }
        }
    }
    private var bootloader: BootloaderInfoResponse.Bootloader? {
        didSet {
            guard let bootloader else { return }
            deviceStatusDelegate?.bootloaderNameReceived(bootloader.description)
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
        
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.dynamicColor(light: .systemBackground, dark: .secondarySystemBackground)
           
            tabBar.tintColor = .nordic
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        } else {
            tabBar.tintColor = .nordic
            tabBar.isTranslucent = false
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        transport?.close()
    }
}

// MARK: - PeripheralDelegate

extension BaseViewController: PeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        self.state = state
        
        if state == .connected {
            let defaultManager = DefaultManager(transport: transport)
            defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            defaultManager.params { [weak self] response, error in
                if let count = response?.bufferCount,
                   let size = response?.bufferSize {
                    self?.mcuMgrParams = (Int(count), Int(size))
                }
                defaultManager.applicationInfo(format: [.kernelName, .kernelVersion]) { [weak self] response, error in
                    self?.appInfoOutput = response?.response

                    defaultManager.bootloaderInfo(query: .name) { [weak self] response, error in
                        self?.bootloader = response?.bootloader
                        guard response?.bootloader == .mcuboot else { return }
                        defaultManager.bootloaderInfo(query: .mode) { [weak self] response, error in
                            self?.bootloaderMode = response?.mode
                        }
                    }
                }
            }
        }
    }
    
}
