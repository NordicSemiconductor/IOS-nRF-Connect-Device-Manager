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
    
    var transport: McuMgrTransport!
    var peripheral: DiscoveredPeripheral! {
        didSet {
            let bleTransport = McuMgrBleTransport(peripheral.basePeripheral)
            bleTransport.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            bleTransport.delegate = self
            transport = bleTransport
            
            // Update transport for all child view controllers
            updateChildTransports()
        }
    }
    
    private var _state: PeripheralState? {
        didSet {
            if let state = _state {
                deviceStatusDelegate?.connectionStateDidChange(state)
            }
        }
    }
    
    public var state: PeripheralState? {
        return _state
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
        
        // Add Memfault tab
        addNRFCloudTab()
        
        // Check if we have a firmware URL from Memfault OTA
        if let firmwarePath = UserDefaults.standard.string(forKey: "pendingFirmwareURL") {
            let firmwareURL = URL(fileURLWithPath: firmwarePath)
            // Clear the stored path to prevent repeated launches
            UserDefaults.standard.removeObject(forKey: "pendingFirmwareURL")
            
            // Switch to the Image tab and start firmware update
            DispatchQueue.main.async { [weak self] in
                self?.selectedIndex = 0 // Select the Image tab
                
                // Notify the Image controller about the firmware
                NotificationCenter.default.post(
                    name: Notification.Name("MemfaultFirmwareReady"),
                    object: nil,
                    userInfo: ["firmwareURL": firmwareURL]
                )
            }
        }
    }
    
    private func addNRFCloudTab() {
        
        // Create nRF Cloud view controller
        let nrfVC = NRFViewController()
        
        // Create navigation controller for consistency with other tabs
        let navController = UINavigationController(rootViewController: nrfVC)
        navController.navigationBar.prefersLargeTitles = false
        
        // Set tab bar item
        let tabItem = UITabBarItem(title: "nRF Cloud", image: nil, selectedImage: nil)
        if #available(iOS 13.0, *) {
            tabItem.image = UIImage(systemName: "icloud.and.arrow.down")
        } else {
            // Fallback for iOS 12
            tabItem.title = "nRF Cloud"
        }
        navController.tabBarItem = tabItem
        
        // Add to existing view controllers
        if var controllers = viewControllers {
            controllers.append(navController)
            setViewControllers(controllers, animated: false)
            
            // Update transports now that the new tab is added
            if transport != nil {
                updateChildTransports()
            }
        }
    }
    
    private func updateChildTransports() {
        guard let transport = transport else { 
            return 
        }
        
        
        // Update transport for NRFViewController which is added programmatically
        if let viewControllers = viewControllers {
            for controller in viewControllers {
                if let navController = controller as? UINavigationController {
                    if let nrfVC = navController.viewControllers.first as? NRFViewController {
                        nrfVC.transport = transport
                    } else {
                    }
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        transport?.close()
    }
}

// MARK: - PeripheralDelegate

extension BaseViewController: PeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        self._state = state
        
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
                        
                        defaultManager.bootloaderInfo(query: .slot) { [weak self] response, error in
                            self?.bootloaderSlot = response?.activeSlot
                        }
                    }
                }
            }
        }
    }
    
}
