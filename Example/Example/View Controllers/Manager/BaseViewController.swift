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
    func bootloaderSlotReceived(_ slot: UInt64)
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
            if let bootloaderSlot {
                deviceStatusDelegate?.bootloaderSlotReceived(bootloaderSlot)
            }
            if let appInfoOutput {
                deviceStatusDelegate?.appInfoReceived(appInfoOutput)
            }
            if let mcuMgrParams {
                deviceStatusDelegate?.mcuMgrParamsReceived(buffers: mcuMgrParams.buffers, size: mcuMgrParams.size)
            }
        }
    }
    
    /**
     Keep an independent transport for any requests ``BaseViewController`` might do.
     
     This is to prevent overlap of sequence numbers used by parallel operations, such
     as ``FirmwareUpgradeManager`` and this ``BaseViewController`` launching parallel requests
     for Bootloader Information, and having them land on the same `McuSequenceNumber` which
     will trigger an assertion failure, specifically in ``McuMgrBleTransport``.
     */
    private var privateTransport: McuMgrTransport!
    
    /**
     Shared ``McuMgrTransport`` for subclasses to use.
     */
    var transport: McuMgrTransport!
    
    var peripheral: DiscoveredPeripheral! {
        didSet {
            let bleTransport = McuMgrBleTransport(peripheral.basePeripheral, DefaultMcuMgrUuidConfig())
            bleTransport.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            bleTransport.delegate = self
            transport = bleTransport
            // Independent transport for BaseViewController operations.
            privateTransport = McuMgrBleTransport(peripheral.basePeripheral, DefaultMcuMgrUuidConfig())
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
    private var bootloaderSlot: UInt64? {
        didSet {
            if let bootloaderSlot {
                deviceStatusDelegate?.bootloaderSlotReceived(bootloaderSlot)
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
            let defaultManager = DefaultManager(transport: privateTransport)
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
                        
                        defaultManager.bootloaderInfo(query: .slot) { [weak self] response, error in
                            self?.bootloaderSlot = response?.activeSlot
                        }
                    }
                }
            }
        }
    }
    
}
