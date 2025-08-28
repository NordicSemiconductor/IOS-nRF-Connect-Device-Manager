//
//  ImageController+NRFCloud.swift
//  nRF Connect Device Manager
//
//  nRF Cloud OTA functionality extension
//

import UIKit
import CoreBluetooth
import iOSMcuManagerLibrary
import SwiftCBOR
import ObjectiveC

// MARK: - NRF Cloud OTA Extension

extension ImageController {
    
    // MARK: - Setup
    
    func setupNRFCloudOTA() {
        // Initial status
        updateNRFCloudStatus("Not connected")
        
        // Make sure button is enabled by default
        checkForUpdatesButton?.isEnabled = true
        
        // Hide update rows initially
        hideUpdateRows()
        
        // Initialize DeviceInfoHelper for FirmwareUpgradeViewController if needed
        if let firmwareVC = firmwareUpgradeVC {
            if firmwareVC.deviceInfoHelper == nil {
                firmwareVC.deviceInfoHelper = DeviceInfoHelper()
                // Create some test device info for now
                let testInfo = DeviceInfoHelper.DeviceInfo(
                    deviceIdentifier: "test-device",
                    hardwareVersion: "1.0.0",
                    softwareType: "main",
                    appVersion: "1.0.0",
                    projectKey: nil,
                    hasMDS: false,
                    hasDIS: true
                )
                firmwareVC.deviceInfoHelper?.updateDeviceInfo(testInfo)
            }
        } else {
            print("[NRFCloud] Warning: FirmwareUpgradeViewController not found")
        }
        
        // Check if we're already connected
        if let baseController = parent as? BaseViewController,
           let transport = baseController.transport as? McuMgrBleTransport {
            if transport.state == .connected {
                checkConnectionAndServices()
            }
        }
    }
    
    func checkConnectionAndServices() {
        guard let firmwareVC = firmwareUpgradeVC else {
            print("[NRFCloud] FirmwareUpgradeViewController not available")
            // Still allow checking for updates even without the firmware VC
            updateNRFCloudStatus("Ready to check for updates")
            // Only enable button if we're not in the middle of an update check
            if !isCheckingForUpdate {
                checkForUpdatesButton?.isEnabled = true
            }
            return
        }
        
        // Get device info to check for services
        if let deviceInfo = firmwareVC.deviceInfoHelper?.getLastDeviceInfo() {
            if deviceInfo.hasMDS {
                updateNRFCloudStatus("Ready to check for updates")
                // Only enable button if we're not in the middle of an update check
                if !isCheckingForUpdate {
                    checkForUpdatesButton?.isEnabled = true
                }
            } else {
                // Even without MDS, we can still check for OTA updates
                updateNRFCloudStatus("Ready to check for updates")
                // Only enable button if we're not in the middle of an update check
                if !isCheckingForUpdate {
                    checkForUpdatesButton?.isEnabled = true
                }
            }
        } else {
            // Device info not available yet, but still allow checking
            updateNRFCloudStatus("Ready to check for updates")
            // Only enable button if we're not in the middle of an update check
            if !isCheckingForUpdate {
                checkForUpdatesButton?.isEnabled = true
            }
        }
    }
    
    // MARK: - IBActions
    
    @IBAction func checkForNRFCloudUpdate(_ sender: UIButton) {
        // Prevent multiple clicks while processing
        guard checkForUpdatesButton?.isEnabled == true else {
            return
        }
        
        // Mark that we're checking for update
        isCheckingForUpdate = true
        
        // If not connected, trigger connection
        if let baseController = parent as? BaseViewController,
           let transport = baseController.transport as? McuMgrBleTransport {
            if transport.state != .connected {
                updateNRFCloudStatus("Connecting...")
                // The connection will be triggered by the scanner
                return
            }
        }
        
        updateNRFCloudStatus("Checking for updates...")
        checkForUpdatesButton?.isEnabled = false
        
        // Initialize the FirmwareUpgradeViewController properties if available
        if firmwareUpgradeVC == nil {
            print("[NRFCloud] Warning: FirmwareUpgradeViewController not found, using defaults")
        }
        
        // Check if we have a BLE transport to read MDS
        if let baseController = parent as? BaseViewController,
           let transport = baseController.transport as? McuMgrBleTransport,
           let peripheral = transport.peripheral {
                print("[NRFCloud] Checking for MDS service on peripheral")
                print("[NRFCloud] Available services: \(peripheral.services?.map { $0.uuid.uuidString } ?? [])")
                
                // If services haven't been fully discovered, trigger discovery
                if peripheral.services == nil || peripheral.services?.count == 1 {
                    print("[NRFCloud] Limited services found, triggering full discovery...")
                    peripheral.discoverServices(nil)
                    
                    // Wait for discovery then continue (without re-enabling the button)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        // Don't re-enable the button, just continue the flow
                        self?.continueCheckAfterServiceDiscovery(sender: sender, peripheral: peripheral, transport: transport)
                    }
                    return
                }
                
                // Look for MDS service (UUID: 54220000-F6A5-4007-A371-722F4EBD8436)
                if let mdsService = peripheral.services?.first(where: { $0.uuid.uuidString.uppercased() == "54220000-F6A5-4007-A371-722F4EBD8436" }) {
                    print("[NRFCloud] Found MDS service, discovering characteristics...")
                    
                    // Discover characteristics if not already done
                    if mdsService.characteristics == nil {
                        peripheral.discoverCharacteristics(nil, for: mdsService)
                        
                        // Wait for discovery then continue
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            self?.continueCheckWithMDSService(mdsService: mdsService, peripheral: peripheral)
                        }
                        return
                    }
                    
                    print("[NRFCloud] MDS characteristics: \(mdsService.characteristics?.map { $0.uuid.uuidString } ?? [])")
                    
                    // Try all MDS characteristics to find the project key
                    print("[NRFCloud] Checking all MDS characteristics for project key...")
                    
                    // Check each characteristic
                    for characteristic in mdsService.characteristics ?? [] {
                        print("[NRFCloud] Reading characteristic: \(characteristic.uuid.uuidString)")
                        peripheral.readValue(for: characteristic)
                    }
                    
                    // Look for Auth characteristic (UUID: 54220001-F6A5-4007-A371-722F4EBD8436)
                    if let authCharacteristic = mdsService.characteristics?.first(where: { $0.uuid.uuidString.uppercased() == "54220001-F6A5-4007-A371-722F4EBD8436" }) {
                        print("[NRFCloud] Found Auth characteristic (54220001), checking value...")
                        
                        // Wait a bit for the reads to complete and check all values
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: { [weak self] in
                            // Check all MDS characteristics
                            print("[NRFCloud] MDS characteristic values after read:")
                            var foundProjectKey: String? = nil
                            
                            for characteristic in mdsService.characteristics ?? [] {
                                if let data = characteristic.value {
                                    print("  - \(characteristic.uuid.uuidString): (hex) \(data.map { String(format: "%02x", $0) }.joined())")
                                    if data.count > 1 {
                                        if let utf8String = String(data: data, encoding: .utf8) {
                                            print("    (UTF-8) \(utf8String)")
                                            
                                            // Check if this is the Authorization characteristic (54220004) with project key
                                            if characteristic.uuid.uuidString.uppercased() == "54220004-F6A5-4007-A371-722F4EBD8436",
                                               utf8String.contains("Memfault-Project-Key:") {
                                                // Extract the project key from the header format
                                                let components = utf8String.split(separator: ":")
                                                if components.count >= 2 {
                                                    foundProjectKey = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                    print("[NRFCloud] Found project key in Authorization characteristic: \(foundProjectKey!)")
                                                }
                                            }
                                        } else {
                                            print("    (UTF-8) not UTF-8")
                                        }
                                    }
                                }
                            }
                            
                            // Use the found project key if available
                            if let projectKey = foundProjectKey {
                                print("[NRFCloud] Using project key from MDS: \(projectKey)")
                                UserDefaults.standard.set(projectKey, forKey: "memfault_project_key")
                                self?.performUpdateCheck(with: projectKey)
                                return
                            }
                            
                            if let authData = authCharacteristic.value {
                                print("[NRFCloud] Auth (54220001) data received (hex): \(authData.map { String(format: "%02x", $0) }.joined())")
                                print("[NRFCloud] Auth (54220001) data length: \(authData.count) bytes")
                                
                                // Check if auth data is valid (not empty or just zeros)
                                let isValidData = authData.count > 1 && authData.contains(where: { $0 != 0x00 })
                                
                                if isValidData {
                                    if authData.count >= 36 {  // Project key is typically 36 bytes (UUID format)
                                        // Extract project key from auth data
                                        // The auth data format is typically: [1 byte type][36 bytes project key][remaining device ID]
                                        let projectKeyData = authData.subdata(in: 1..<min(37, authData.count))
                                        if let key = String(data: projectKeyData, encoding: .utf8), !key.isEmpty {
                                            print("[NRFCloud] Got project key from MDS: \(key)")
                                            // Store it for future use
                                            UserDefaults.standard.set(key, forKey: "memfault_project_key")
                                            // Continue with the check using this key
                                            self?.performUpdateCheck(with: key)
                                            return
                                        } else {
                                            print("[NRFCloud] Could not decode project key as UTF-8")
                                        }
                                    } else {
                                        // Try using the entire data as the key
                                        if let key = String(data: authData, encoding: .utf8), !key.isEmpty {
                                            print("[NRFCloud] Got project key from MDS (full data): \(key)")
                                            UserDefaults.standard.set(key, forKey: "memfault_project_key")
                                            self?.performUpdateCheck(with: key)
                                            return
                                        }
                                    }
                                } else {
                                    print("[NRFCloud] MDS Auth characteristic is empty or not configured")
                                    
                                    // Try Device ID characteristic (54220002) which might contain the project key
                                    if let deviceIdChar = mdsService.characteristics?.first(where: { $0.uuid.uuidString.uppercased() == "54220002-F6A5-4007-A371-722F4EBD8436" }),
                                       let deviceIdData = deviceIdChar.value,
                                       deviceIdData.count >= 36 {
                                        // Try extracting project key from device ID data
                                        if let key = String(data: deviceIdData, encoding: .utf8), key.contains("-") {
                                            print("[NRFCloud] Found project key in Device ID characteristic: \(key)")
                                            UserDefaults.standard.set(key, forKey: "memfault_project_key")
                                            self?.performUpdateCheck(with: key)
                                            return
                                        }
                                    }
                                }
                            } else {
                                print("[NRFCloud] Auth characteristic value is nil after read")
                            }
                            
                            // If we couldn't get it from MDS, fall back to stored key
                            print("[NRFCloud] Failed to get project key from MDS, using stored key")
                            self?.checkForUpdateWithStoredKey(sender: sender)
                        })
                        return
                    } else {
                        print("[NRFCloud] Auth characteristic not found in MDS service")
                    }
                } else {
                    print("[NRFCloud] MDS service not found on peripheral")
                }
        } else {
            print("[NRFCloud] Unable to get peripheral from transport")
        }
        
        // If no MDS service or peripheral not found, use stored key
        checkForUpdateWithStoredKey(sender: sender)
    }
    
    private func continueCheckAfterServiceDiscovery(sender: UIButton, peripheral: CBPeripheral, transport: McuMgrBleTransport) {
        // This is called after service discovery completes
        // Continue with MDS service check
        print("[NRFCloud] Services after discovery: \(peripheral.services?.map { $0.uuid.uuidString } ?? [])")
        
        if let mdsService = peripheral.services?.first(where: { $0.uuid.uuidString.uppercased() == "54220000-F6A5-4007-A371-722F4EBD8436" }) {
            continueCheckWithMDSService(mdsService: mdsService, peripheral: peripheral)
        } else {
            print("[NRFCloud] MDS service not found after discovery")
            checkForUpdateWithStoredKey(sender: sender)
        }
    }
    
    private func continueCheckWithMDSService(mdsService: CBService, peripheral: CBPeripheral) {
        // This is called after MDS characteristic discovery completes
        print("[NRFCloud] MDS characteristics after discovery: \(mdsService.characteristics?.map { $0.uuid.uuidString } ?? [])")
        
        // Read all MDS characteristics
        for characteristic in mdsService.characteristics ?? [] {
            print("[NRFCloud] Reading characteristic: \(characteristic.uuid.uuidString)")
            peripheral.readValue(for: characteristic)
        }
        
        // Wait for reads to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.processMDSCharacteristics(mdsService: mdsService)
        }
    }
    
    private func processMDSCharacteristics(mdsService: CBService) {
        print("[NRFCloud] Processing MDS characteristics")
        var foundProjectKey: String? = nil
        
        for characteristic in mdsService.characteristics ?? [] {
            if let data = characteristic.value {
                print("  - \(characteristic.uuid.uuidString): (hex) \(data.map { String(format: "%02x", $0) }.joined())")
                if data.count > 1 {
                    if let utf8String = String(data: data, encoding: .utf8) {
                        print("    (UTF-8) \(utf8String)")
                        
                        // Check if this is the Authorization characteristic (54220004) with project key
                        if characteristic.uuid.uuidString.uppercased() == "54220004-F6A5-4007-A371-722F4EBD8436",
                           utf8String.contains("Memfault-Project-Key:") {
                            let components = utf8String.split(separator: ":")
                            if components.count >= 2 {
                                foundProjectKey = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                                print("[NRFCloud] Found project key in Authorization characteristic: \(foundProjectKey!)")
                            }
                        }
                    }
                }
            }
        }
        
        if let projectKey = foundProjectKey {
            print("[NRFCloud] Using project key from MDS: \(projectKey)")
            UserDefaults.standard.set(projectKey, forKey: "memfault_project_key")
            performUpdateCheck(with: projectKey)
        } else {
            print("[NRFCloud] Failed to get project key from MDS, using stored key")
            checkForUpdateWithStoredKey(sender: UIButton())
        }
    }
    
    private func checkForUpdateWithStoredKey(sender: UIButton) {
        var projectKey: String? = nil
        
        if let storedKey = UserDefaults.standard.string(forKey: "memfault_project_key"),
           !storedKey.isEmpty {
            projectKey = storedKey
        }
        
        guard let key = projectKey else {
            updateNRFCloudStatus("Project key required")
            isCheckingForUpdate = false
            checkForUpdatesButton?.isEnabled = true
            
            // Show alert to get project key
            let alert = UIAlertController(
                title: "Project Key Required",
                message: "Enter your Memfault project key (found in Settings → Project Key on memfault.com)",
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.placeholder = "Project key (e.g., abc123de-4567-890f-ghij-klmnopqrstuv)"
                textField.text = UserDefaults.standard.string(forKey: "memfault_project_key")
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                self.isCheckingForUpdate = false
                self.checkForUpdatesButton?.isEnabled = true
            })
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                if let projectKey = alert.textFields?.first?.text, !projectKey.isEmpty {
                    UserDefaults.standard.set(projectKey, forKey: "memfault_project_key")
                    self.performUpdateCheck(with: projectKey)
                } else {
                    self.isCheckingForUpdate = false
                    self.checkForUpdatesButton?.isEnabled = true
                }
            })
            present(alert, animated: true)
            return
        }
        
        performUpdateCheck(with: key)
    }
    
    private func performUpdateCheck(with projectKey: String) {
        updateNRFCloudStatus("Checking for updates...")
        checkForUpdatesButton?.isEnabled = false
        
        print("[NRFCloud] performUpdateCheck called with project key: \(projectKey)")
        
        // Try to read device info from DIS service first
        readDeviceInfoFromDIS { [weak self] disInfo in
            // Get device information for the update check or use defaults
            let deviceInfo: DeviceInfoHelper.DeviceInfo
            if let firmwareVC = self?.firmwareUpgradeVC,
               let info = firmwareVC.deviceInfoHelper?.getLastDeviceInfo() {
                print("[NRFCloud] Using device info from FirmwareUpgradeViewController")
                deviceInfo = info
            } else if let disInfo = disInfo {
                print("[NRFCloud] Using device info from DIS service")
                deviceInfo = disInfo
            } else {
                print("[NRFCloud] Using default device info (FirmwareUpgradeVC not available)")
                // Use default device info
                deviceInfo = DeviceInfoHelper.DeviceInfo(
                    deviceIdentifier: "nrf-device",
                    hardwareVersion: "1.0.0",
                    softwareType: "main",
                    appVersion: "1.0.0",
                    projectKey: nil,
                    hasMDS: false,
                    hasDIS: true
                )
            }
            
            self?.continueUpdateCheck(with: projectKey, deviceInfo: deviceInfo)
        }
    }
    
    private func readDeviceInfoFromDIS(completion: @escaping (DeviceInfoHelper.DeviceInfo?) -> Void) {
        guard let baseController = parent as? BaseViewController,
              let transport = baseController.transport as? McuMgrBleTransport,
              let peripheral = transport.peripheral else {
            completion(nil)
            return
        }
        
        // Look for DIS service (UUID: 180A)
        guard let disService = peripheral.services?.first(where: { $0.uuid.uuidString.uppercased() == "180A" }) else {
            print("[NRFCloud] DIS service not found")
            completion(nil)
            return
        }
        
        // Discover characteristics if needed
        if disService.characteristics == nil {
            peripheral.discoverCharacteristics(nil, for: disService)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.readDeviceInfoFromDIS(completion: completion)
            }
            return
        }
        
        // Read all DIS characteristics
        var hardwareRevision: String?
        var softwareRevision: String?
        var manufacturerName: String?
        var modelNumber: String?
        var firmwareRevision: String?
        var serialNumber: String?
        var pnpId: String?
        
        for characteristic in disService.characteristics ?? [] {
            peripheral.readValue(for: characteristic)
        }
        
        // Wait for reads to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for characteristic in disService.characteristics ?? [] {
                if let data = characteristic.value {
                    if let value = String(data: data, encoding: .utf8) {
                        switch characteristic.uuid.uuidString.uppercased() {
                        case "2A24": // Model Number String
                            modelNumber = value
                            print("[NRFCloud] DIS Model Number (2A24): \(value)")
                        case "2A25": // Serial Number String
                            serialNumber = value
                            print("[NRFCloud] DIS Serial Number (2A25): \(value)")
                        case "2A26": // Firmware Revision String
                            firmwareRevision = value
                            print("[NRFCloud] DIS Firmware Revision (2A26): \(value)")
                        case "2A27": // Hardware Revision
                            hardwareRevision = value
                            print("[NRFCloud] DIS Hardware Revision (2A27): \(value)")
                        case "2A28": // Software Revision
                            softwareRevision = value
                            print("[NRFCloud] DIS Software Revision (2A28): \(value)")
                        case "2A29": // Manufacturer Name
                            manufacturerName = value
                            print("[NRFCloud] DIS Manufacturer (2A29): \(value)")
                        case "2A50": // PnP ID
                            // This might be binary data, try to decode
                            if data.count > 0 {
                                // PnP ID format: Vendor ID Source (1 byte) + Vendor ID (2 bytes) + Product ID (2 bytes) + Product Version (2 bytes)
                                print("[NRFCloud] DIS PnP ID (2A50) raw data: \(data.map { String(format: "%02x", $0) }.joined())")
                            }
                        default:
                            print("[NRFCloud] DIS Unknown characteristic \(characteristic.uuid.uuidString): \(value)")
                        }
                    } else {
                        // Try to decode as hex for non-UTF8 data
                        print("[NRFCloud] DIS characteristic \(characteristic.uuid.uuidString) (hex): \(data.map { String(format: "%02x", $0) }.joined())")
                    }
                }
            }
            
            // Get device ID from MDS if available
            var deviceId = "nrf-device"
            // Default software type to "main" as that's what the device is using
            var softwareType = "main"
            
            if let mdsService = peripheral.services?.first(where: { $0.uuid.uuidString.uppercased() == "54220000-F6A5-4007-A371-722F4EBD8436" }) {
                // Get Device ID from characteristic 54220002
                if let deviceIdChar = mdsService.characteristics?.first(where: { $0.uuid.uuidString.uppercased() == "54220002-F6A5-4007-A371-722F4EBD8436" }),
                   let deviceIdData = deviceIdChar.value,
                   let deviceIdString = String(data: deviceIdData, encoding: .utf8) {
                    deviceId = deviceIdString
                    print("[NRFCloud] MDS Device ID: \(deviceId)")
                }
                
                // Note: We should NOT parse the chunk data (54220005) - it's meant to be opaque data
                // forwarded to the cloud. The software type should come from device configuration
                // or be hardcoded based on the device's actual build.
            }
            
            let appVersion = softwareRevision ?? firmwareRevision ?? "1.0.0"
            
            let deviceInfo = DeviceInfoHelper.DeviceInfo(
                deviceIdentifier: deviceId,
                hardwareVersion: hardwareRevision ?? "1.0.0",
                softwareType: softwareType,
                appVersion: appVersion,
                projectKey: nil,
                hasMDS: true,
                hasDIS: hardwareRevision != nil
            )
            
            print("[NRFCloud] Final device info:")
            print("  - Device ID: \(deviceId)")
            print("  - Hardware Version: \(hardwareRevision ?? "1.0.0")")
            print("  - Software Type: \(softwareType)")
            print("  - App Version: \(appVersion)")
            
            completion(deviceInfo)
        }
    }
    
    private func continueUpdateCheck(with projectKey: String, deviceInfo: DeviceInfoHelper.DeviceInfo) {
        
        // Create OTA manager and check for updates
        let otaManager: MemfaultOTAManager
        if let firmwareVC = firmwareUpgradeVC {
            otaManager = firmwareVC.memfaultOTAManager ?? MemfaultOTAManager()
            firmwareVC.memfaultOTAManager = otaManager
        } else {
            otaManager = MemfaultOTAManager()
        }
        
        otaManager.checkForUpdate(
            projectKey: projectKey,
            deviceId: deviceInfo.deviceIdentifier ?? "unknown",
            hardwareVersion: deviceInfo.hardwareVersion ?? "1.0.0",
            softwareType: deviceInfo.softwareType ?? "app",
            currentVersion: deviceInfo.appVersion ?? "0.0.0",
            extraQuery: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isCheckingForUpdate = false
                self?.checkForUpdatesButton?.isEnabled = true
                
                switch result {
                case .success(let updateInfo):
                    self?.firmwareUpgradeVC?.currentUpdateInfo = updateInfo
                    
                    if let latestVersion = updateInfo.version {
                        let currentVersion = deviceInfo.appVersion ?? "0.0.0"
                        if latestVersion == currentVersion {
                            self?.updateNRFCloudStatus("You're running the latest version (\(currentVersion))")
                            self?.hideUpdateRows()
                        } else {
                            self?.updateNRFCloudStatus("Update available!")
                            self?.showUpdateInfo(updateInfo)
                        }
                    } else {
                        self?.updateNRFCloudStatus("No updates available")
                        self?.hideUpdateRows()
                    }
                    
                case .failure(let error):
                    // Check for "no update available" error first
                    if let otaError = error as? MemfaultOTAManager.OTAError,
                       otaError == .noUpdateAvailable {
                        let currentVersion = deviceInfo.appVersion ?? "0.0.0"
                        self?.updateNRFCloudStatus("You're running the latest version (\(currentVersion))")
                        self?.hideUpdateRows()
                        return
                    }
                    
                    // Show detailed error message
                    let errorMessage: String
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .notConnectedToInternet:
                            errorMessage = "No internet connection"
                        case .timedOut:
                            errorMessage = "Request timed out"
                        default:
                            errorMessage = "Network error: \(urlError.localizedDescription)"
                        }
                    } else if let nsError = error as NSError? {
                        if nsError.domain == "MemfaultOTA" {
                            // Check for HTTP status code in userInfo
                            if let statusCode = nsError.userInfo["statusCode"] as? Int {
                                switch statusCode {
                                case 401:
                                    errorMessage = "Invalid project key (401)"
                                case 403:
                                    errorMessage = "Access forbidden (403)"
                                case 404:
                                    errorMessage = "No updates found (404)"
                                case 500...599:
                                    errorMessage = "Server error (\(statusCode))"
                                default:
                                    errorMessage = "Error \(statusCode): \(nsError.localizedDescription)"
                                }
                            } else {
                                errorMessage = nsError.localizedDescription
                            }
                        } else {
                            errorMessage = error.localizedDescription
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    
                    self?.updateNRFCloudStatus("Error: \(errorMessage)")
                    self?.hideUpdateRows()
                }
            }
        }
    }
    
    @IBAction func downloadAndInstallUpdate(_ sender: UIButton) {
        guard let updateInfo = firmwareUpgradeVC?.currentUpdateInfo,
              let downloadUrl = updateInfo.url else {
            updateNRFCloudStatus("No update information available")
            return
        }
        
        updateNRFCloudStatus("Downloading update...")
        downloadInstallButton?.isEnabled = false
        
        // Start listening for progress notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(firmwareUpgradeProgressChanged(_:)),
            name: Notification.Name("FirmwareUpgradeProgressChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(firmwareUpgradeStateChanged(_:)),
            name: Notification.Name("FirmwareUpgradeStateChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(firmwareUpgradeFailed(_:)),
            name: Notification.Name("FirmwareUpgradeFailed"),
            object: nil
        )
        
        // Download the firmware
        let task = URLSession.shared.downloadTask(with: URL(string: downloadUrl)!) { [weak self] url, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.updateNRFCloudStatus("Download failed: \(error.localizedDescription)")
                    self?.downloadInstallButton?.isEnabled = true
                    return
                }
                
                guard let url = url else {
                    self?.updateNRFCloudStatus("Download failed")
                    self?.downloadInstallButton?.isEnabled = true
                    return
                }
                
                // Move the file to a permanent location
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent("firmware_update.zip")
                
                do {
                    // Remove existing file if present
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.moveItem(at: url, to: destinationURL)
                    
                    // Parse the firmware package
                    guard let firmwareVC = self?.firmwareUpgradeVC else {
                        self?.updateNRFCloudStatus("Firmware upgrade controller not available")
                        self?.downloadInstallButton?.isEnabled = true
                        return
                    }
                    
                    // Use the firmware upgrade view controller to handle the update
                    switch firmwareVC.parseAsMcuMgrPackage(destinationURL) {
                    case .success(let package):
                        firmwareVC.package = package
                        self?.updateNRFCloudStatus("Starting installation...")
                        
                        // Start the firmware upgrade
                        firmwareVC.startFirmwareUpgrade(package: package)
                        
                    case .failure(let error):
                        self?.updateNRFCloudStatus("Invalid firmware: \(error.localizedDescription)")
                        self?.downloadInstallButton?.isEnabled = true
                    }
                    
                } catch {
                    self?.updateNRFCloudStatus("Failed to save firmware: \(error.localizedDescription)")
                    self?.downloadInstallButton?.isEnabled = true
                }
            }
        }
        task.resume()
    }
    
    // MARK: - Notification Handlers
    
    @objc private func firmwareUpgradeProgressChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let bytesSent = userInfo["bytesSent"] as? Int,
              let imageSize = userInfo["imageSize"] as? Int else {
            return
        }
        
        let percentage = Int((Float(bytesSent) / Float(imageSize)) * 100)
        updateNRFCloudStatus("Installing update: \(percentage)%")
    }
    
    @objc private func firmwareUpgradeStateChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let state = userInfo["state"] as? String else {
            return
        }
        
        switch state {
        case "success":
            updateNRFCloudStatus("Update installed successfully!")
            downloadInstallButton?.isEnabled = true
            hideUpdateRows()
            // Clean up notifications
            NotificationCenter.default.removeObserver(self, name: Notification.Name("FirmwareUpgradeProgressChanged"), object: nil)
            NotificationCenter.default.removeObserver(self, name: Notification.Name("FirmwareUpgradeStateChanged"), object: nil)
            NotificationCenter.default.removeObserver(self, name: Notification.Name("FirmwareUpgradeFailed"), object: nil)
        case "reset":
            updateNRFCloudStatus("Resetting device...")
        case "confirm":
            updateNRFCloudStatus("Confirming update...")
        case "upload":
            updateNRFCloudStatus("Uploading firmware...")
        default:
            break
        }
    }
    
    @objc private func firmwareUpgradeFailed(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let error = userInfo["error"] as? String else {
            updateNRFCloudStatus("Update failed")
            downloadInstallButton?.isEnabled = true
            return
        }
        
        updateNRFCloudStatus("Update failed: \(error)")
        downloadInstallButton?.isEnabled = true
        
        // Clean up notifications
        NotificationCenter.default.removeObserver(self, name: Notification.Name("FirmwareUpgradeProgressChanged"), object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("FirmwareUpgradeStateChanged"), object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("FirmwareUpgradeFailed"), object: nil)
    }
    
    // MARK: - UI Updates
    
    private func showUpdateInfo(_ updateInfo: MemfaultOTAManager.UpdateInfo) {
        updateVersionLabel?.text = updateInfo.version ?? "Unknown"
        updateSizeLabel?.text = formatBytes(updateInfo.size ?? 0)
        updateDescriptionLabel?.text = updateInfo.releaseNotes ?? "No description available"
        
        // Show the update rows
        updateInfoCell?.isHidden = false
        actionButtonsCell?.isHidden = false
        
        // Force complete table reload to recalculate heights
        tableView.reloadData()
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Helper Properties
    
    private var firmwareUpgradeVC: FirmwareUpgradeViewController? {
        // The FirmwareUpgradeViewController is embedded in a container view in the first cell
        // of the IMAGE UPGRADE section (section 1)
        
        // First, try to get it from the visible cells
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 1)) {
            // Look for container view which hosts the FirmwareUpgradeViewController
            for subview in cell.contentView.subviews {
                if let containerView = subview as? UIView {
                    // Check if there's a FirmwareUpgradeViewController as a child view controller
                    let parentVC = self.parent ?? self
                    for childVC in parentVC.children {
                        if let firmwareVC = childVC as? FirmwareUpgradeViewController {
                            return firmwareVC
                        }
                    }
                }
            }
        }
        
        // Alternative approach: check the parent's children directly
        let parentVC = self.parent ?? self
        for childVC in parentVC.children {
            if let firmwareVC = childVC as? FirmwareUpgradeViewController {
                return firmwareVC
            }
        }
        
        return nil
    }
}

// MARK: - Supporting Types

class MemfaultOTAManager {
    struct UpdateInfo {
        let version: String?
        let url: String?
        let size: Int?
        let releaseNotes: String?
    }
    
    enum OTAError: Error, Equatable {
        case invalidResponse
        case noUpdateAvailable
        case networkError(Error)
        
        static func == (lhs: OTAError, rhs: OTAError) -> Bool {
            switch (lhs, rhs) {
            case (.invalidResponse, .invalidResponse):
                return true
            case (.noUpdateAvailable, .noUpdateAvailable):
                return true
            case (.networkError(_), .networkError(_)):
                return true  // We consider any network errors as equal for simplicity
            default:
                return false
            }
        }
    }
    
    func checkForUpdate(
        projectKey: String,
        deviceId: String,
        hardwareVersion: String,
        softwareType: String,
        currentVersion: String,
        extraQuery: String?,
        completion: @escaping (Result<UpdateInfo, Error>) -> Void
    ) {
        // Build the API URL
        var components = URLComponents(string: "https://api.memfault.com/api/v0/releases/latest")!
        components.queryItems = [
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "hardware_version", value: hardwareVersion),
            URLQueryItem(name: "software_type", value: softwareType),
            URLQueryItem(name: "current_version", value: currentVersion)
        ]
        
        if let extra = extraQuery {
            components.queryItems?.append(URLQueryItem(name: "extra", value: extra))
        }
        
        var request = URLRequest(url: components.url!)
        request.setValue(projectKey, forHTTPHeaderField: "Memfault-Project-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        print("[NRFCloud] API Request URL: \(components.url!)")
        print("[NRFCloud] Using Project Key: \(projectKey)")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(OTAError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(OTAError.invalidResponse))
                return
            }
            
            print("[NRFCloud] API Response Status: \(httpResponse.statusCode)")
            
            // Check status code
            if httpResponse.statusCode == 204 {
                // 204 No Content means no update available
                print("[NRFCloud] No update available (204 No Content)")
                completion(.failure(OTAError.noUpdateAvailable))
                return
            } else if httpResponse.statusCode != 200 {
                if httpResponse.statusCode == 401 {
                    print("[NRFCloud] ERROR 401: Unauthorized - Project key may be incorrect")
                }
                if let data = data, let errorText = String(data: data, encoding: .utf8) {
                    print("[NRFCloud] Error response body: \(errorText)")
                }
                let error = NSError(
                    domain: "MemfaultOTA",
                    code: httpResponse.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)",
                        "statusCode": httpResponse.statusCode
                    ]
                )
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(OTAError.invalidResponse))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let updateInfo = UpdateInfo(
                        version: json["version"] as? String,
                        url: json["url"] as? String,
                        size: json["size"] as? Int,
                        releaseNotes: json["release_notes"] as? String
                    )
                    
                    if updateInfo.url != nil {
                        completion(.success(updateInfo))
                    } else {
                        completion(.failure(OTAError.noUpdateAvailable))
                    }
                } else {
                    completion(.failure(OTAError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}

