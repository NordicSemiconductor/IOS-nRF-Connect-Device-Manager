/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import CoreBluetooth
import iOSMcuManagerLibrary
import iOSOtaLibrary

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
    
    // MARK: Properties
    
    weak var deviceStatusDelegate: DeviceStatusDelegate? {
        didSet {
            if let peripheralState {
                deviceStatusDelegate?.connectionStateDidChange(peripheralState)
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
     Shared ``McuMgrTransport`` for subclasses to use.
     */
    var transport: McuMgrTransport!
    
    var peripheral: DiscoveredPeripheral! {
        didSet {
            let bleTransport = McuMgrBleTransport(peripheral.basePeripheral)
            bleTransport.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            bleTransport.delegate = self
            transport = bleTransport
        }
    }
    
    // MARK: Private Properties
    
    private var otaManager: OTAManager?
    private var deviceInfoRequested: Bool = false
    private var statusInfoCallback: (() -> ())?
    
    private var peripheralState: PeripheralState? {
        didSet {
            guard let peripheralState else { return }
            deviceStatusDelegate?.connectionStateDidChange(peripheralState)
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
            guard let bootloaderSlot else { return }
            deviceStatusDelegate?.bootloaderSlotReceived(bootloaderSlot)
        }
    }
    private var appInfoOutput: String? {
        didSet {
            guard let appInfoOutput else { return }
            deviceStatusDelegate?.appInfoReceived(appInfoOutput)
        }
    }
    private var mcuMgrParams: (buffers: Int, size: Int)? {
        didSet {
            guard let mcuMgrParams else { return }
            deviceStatusDelegate?.mcuMgrParamsReceived(buffers: mcuMgrParams.buffers, size: mcuMgrParams.size)
        }
    }
    
    // MARK: viewDidLoad()
    
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
    
    // MARK: viewWillDisappear()
    
    override func viewWillDisappear(_ animated: Bool) {
        transport?.close()
    }
}

// MARK: Device Status

extension BaseViewController {
    
    func onDeviceStatusReady(_ callback: @escaping () -> Void) {
        statusInfoCallback = callback
        guard !deviceInfoRequested else {
            onDeviceStatusFinished()
            return
        }
        
        let defaultManager = DefaultManager(transport: transport)
        defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        defaultManager.params { [weak self] response, error in
            if let count = response?.bufferCount,
               let size = response?.bufferSize {
                self?.mcuMgrParams = (Int(count), Int(size))
            }
            
            self?.requestApplicationInfo(defaultManager)
        }
    }
    
    private func requestApplicationInfo(_ defaultManager: DefaultManager) {
        defaultManager.applicationInfo(format: [.kernelName, .kernelVersion]) { [weak self] response, error in
            self?.appInfoOutput = response?.response
            self?.requestBootloaderInfo(defaultManager)
        }
    }
    
    private func requestBootloaderInfo(_ defaultManager: DefaultManager) {
        defaultManager.bootloaderInfo(query: .name) { [weak self] response, error in
            self?.bootloader = response?.bootloader
            guard response?.bootloader == .mcuboot else {
                self?.onDeviceStatusFinished()
                return
            }
            
            defaultManager.bootloaderInfo(query: .mode) { [weak self] response, error in
                self?.bootloaderMode = response?.mode
                
                defaultManager.bootloaderInfo(query: .slot) { [weak self] response, error in
                    self?.bootloaderSlot = response?.activeSlot
                    self?.onDeviceStatusFinished()
                }
            }
        }
    }
    
    private func onDeviceStatusFinished() {
        guard let statusInfoCallback else { return }
        statusInfoCallback()
        deviceInfoRequested = true
        self.statusInfoCallback = nil
    }
}

// MARK: - PeripheralDelegate

extension BaseViewController: PeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        peripheralState = state
        switch state {
        case .connected:
            otaManager = OTAManager(peripheral.identifier)
            otaManager?.getDeviceInfoToken { [unowned self] result in
                switch result {
                case .success(let deviceInfoToken):
                    print("Obtained Device Info Token \(deviceInfoToken)")
                    otaManager?.getMDSAuthToken { result in
                        switch result {
                        case .success(let mdsAuthToken):
                            print("Obtained MDS Token \(mdsAuthToken)")
                        case .failure(let error):
                            print("Error: \(error.localizedDescription)")
                        }
                    }
                case .failure(let error):
                    print("Error: \(error.localizedDescription)")
                }
            }
        case .disconnecting, .disconnected:
            // Set to false, because a DFU update might change things if that's what happened.
            deviceInfoRequested = false
            otaManager = nil
        default:
            // Nothing to do here.
            break
        }
    }
}
