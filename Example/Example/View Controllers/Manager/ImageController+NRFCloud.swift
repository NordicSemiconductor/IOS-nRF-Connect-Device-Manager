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
    
    // Store one singleton OTA manager instance locally
    private static var nrfCloudOTAManager = NRFCloudOTAManager()
    
    private var otaManager: NRFCloudOTAManager {
        return ImageController.nrfCloudOTAManager
    }
    
    // MARK: - Setup
    
    func setupNRFCloudOTA() {
        // Initial status
        updateNRFCloudStatus("Not connected")
        
        // Make sure button is enabled by default
        checkForUpdatesButton?.isEnabled = true
        
        // Hide update rows initially
        hideUpdateRows()
        
        // Check if we're already connected
        if let baseController = parent as? BaseViewController,
           let transport = baseController.transport as? McuMgrBleTransport {
            if transport.state == .connected {
                checkConnectionAndServices()
            }
        }
    }
    
    func checkConnectionAndServices() {
        // Simply allow checking for updates when connected
        updateNRFCloudStatus("Ready to check for updates")
        // Only enable button if we're not in the middle of an update check
        if !isCheckingForUpdate {
            checkForUpdatesButton?.isEnabled = true
        }
    }
    
    // MARK: - IBActions
    
    @IBAction func learnMoreAboutNRFCloud(_ sender: UIButton) {
        // Open the nRF Cloud services information page in the default browser
        if let url = URL(string: "https://mflt.io/nrf-app-discover-cloud-services") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    @IBAction func checkForNRFCloudUpdate(_ sender: UIButton) {
        // Check if transport is connected first
        guard let baseController = parent as? BaseViewController,
              let transport = baseController.transport as? McuMgrBleTransport else {
            updateNRFCloudStatus("Disconnected")
            return
        }
        
        // If not connected, just show disconnected
        if transport.state != .connected {
            updateNRFCloudStatus("Disconnected")
            return
        }
        
        // Prevent multiple clicks while processing
        guard checkForUpdatesButton?.isEnabled == true else {
            return
        }
        
        // Mark that we're checking for update
        isCheckingForUpdate = true
        updateNRFCloudStatus("Checking for updates...")
        checkForUpdatesButton?.isEnabled = false
        
        // Check if we have access to the connected peripheral through the transport
        guard let peripheral = transport.peripheral else {
            print("[NRFCloud] Unable to get peripheral from transport")
            updateNRFCloudStatus("Error: Unable to access device")
            isCheckingForUpdate = false
            checkForUpdatesButton?.isEnabled = true
            return
        }
        
        print("[NRFCloud] Checking for MDS service on peripheral")
        print("[NRFCloud] Available services: \(peripheral.services?.map { $0.uuid.uuidString } ?? [])")
        
        // If services haven't been fully discovered, trigger discovery
        if peripheral.services == nil || peripheral.services?.count == 1 {
            print("[NRFCloud] Limited services found, triggering full discovery...")
            peripheral.discoverServices(nil)
            
            // Wait for discovery then continue
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.checkForMDSService(peripheral: peripheral)
            }
            return
        }
        
        checkForMDSService(peripheral: peripheral)
    }
    
    private func checkForMDSService(peripheral: CBPeripheral) {
        // Look for MDS service (UUID: 54220000-F6A5-4007-A371-722F4EBD8436)
        guard let mdsService = peripheral.services?.first(where: { $0.uuid.uuidString.uppercased() == "54220000-F6A5-4007-A371-722F4EBD8436" }) else {
            print("[NRFCloud] MDS service not found on peripheral")
            updateNRFCloudStatus("Error: MDS service not found")
            isCheckingForUpdate = false
            checkForUpdatesButton?.isEnabled = true
            return
        }
        
        print("[NRFCloud] Found MDS service")
        
        // Discover characteristics if not already done
        if mdsService.characteristics == nil {
            print("[NRFCloud] Discovering MDS characteristics...")
            peripheral.discoverCharacteristics(nil, for: mdsService)
            
            // Wait for discovery then continue
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.readMDSCharacteristics(mdsService: mdsService, peripheral: peripheral)
            }
            return
        }
        
        readMDSCharacteristics(mdsService: mdsService, peripheral: peripheral)
    }
    
    private func readMDSCharacteristics(mdsService: CBService, peripheral: CBPeripheral) {
        print("[NRFCloud] MDS characteristics: \(mdsService.characteristics?.map { $0.uuid.uuidString } ?? [])")
        
        // Read all MDS characteristics
        for characteristic in mdsService.characteristics ?? [] {
            print("[NRFCloud] Reading characteristic: \(characteristic.uuid.uuidString)")
            peripheral.readValue(for: characteristic)
        }
        
        // Wait for reads to complete then process
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.processMDSCharacteristics(mdsService: mdsService)
        }
    }
    
    
    private func processMDSCharacteristics(mdsService: CBService) {
        print("[NRFCloud] Processing MDS characteristics")
        var foundProjectKey: String? = nil
        var deviceId: String? = nil
        
        for characteristic in mdsService.characteristics ?? [] {
            if let data = characteristic.value {
                let uuidString = characteristic.uuid.uuidString.uppercased()
                print("  - \(uuidString): (hex) \(data.map { String(format: "%02x", $0) }.joined())")
                
                if data.count > 0 {
                    if let utf8String = String(data: data, encoding: .utf8) {
                        print("    (UTF-8) \(utf8String)")
                        
                        // Check for different characteristic types
                        switch uuidString {
                        case "54220002-F6A5-4007-A371-722F4EBD8436": // Device ID
                            deviceId = utf8String
                            print("[NRFCloud] Found Device ID: \(utf8String)")
                            
                        case "54220004-F6A5-4007-A371-722F4EBD8436": // Authorization
                            if utf8String.contains("Memfault-Project-Key:") {
                                let components = utf8String.split(separator: ":")
                                if components.count >= 2 {
                                    foundProjectKey = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    print("[NRFCloud] Found project key in Authorization: \(foundProjectKey!)")
                                }
                            }
                            
                        default:
                            break
                        }
                    }
                }
            }
        }
        
        if let projectKey = foundProjectKey {
            print("[NRFCloud] Using project key from MDS: \(projectKey)")
            // Pass both project key and device ID
            performUpdateCheck(with: projectKey, deviceId: deviceId)
        } else {
            print("[NRFCloud] Failed to get project key from MDS")
            updateNRFCloudStatus("Error: MDS project key not configured")
            isCheckingForUpdate = false
            checkForUpdatesButton?.isEnabled = true
        }
    }
    
    
    private func performUpdateCheck(with projectKey: String, deviceId: String? = nil) {
        updateNRFCloudStatus("Checking for updates...")
        checkForUpdatesButton?.isEnabled = false
        
        print("[NRFCloud] performUpdateCheck called with project key: \(projectKey)")
        
        // Try to read device info from DIS service first
        readDeviceInfoFromDIS(mdsDeviceId: deviceId) { [weak self] disInfo in
            // Get device information for the update check - DIS is required
            guard let deviceInfo = disInfo else {
                print("[NRFCloud] DIS service not available")
                self?.updateNRFCloudStatus("Error: DIS service missing")
                self?.isCheckingForUpdate = false
                self?.checkForUpdatesButton?.isEnabled = true
                return
            }
            
            print("[NRFCloud] Using device info from DIS service")
            self?.continueUpdateCheck(with: projectKey, deviceInfo: deviceInfo)
        }
    }
    
    // Simple struct to hold device info from DIS
    private struct DeviceInfo {
        let deviceId: String
        let hardwareVersion: String
        let softwareType: String
        let appVersion: String
    }
    
    private func readDeviceInfoFromDIS(mdsDeviceId: String? = nil, completion: @escaping (DeviceInfo?) -> Void) {
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
        var firmwareRevision: String?
        var serialNumber: String?

        
        for characteristic in disService.characteristics ?? [] {
            peripheral.readValue(for: characteristic)
        }
        
        // Wait for reads to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for characteristic in disService.characteristics ?? [] {
                if let data = characteristic.value {
                    if let value = String(data: data, encoding: .utf8) {
                        switch characteristic.uuid.uuidString.uppercased() {
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
                        default:
                            // print("[NRFCloud] DIS Unknown characteristic \(characteristic.uuid.uuidString): \(value)")
                            break
                        }
                    } else {
                        // Try to decode as hex for non-UTF8 data
                        print("[NRFCloud] DIS characteristic \(characteristic.uuid.uuidString) (hex): \(data.map { String(format: "%02x", $0) }.joined())")
                    }
                }
            }
            

            if ((serialNumber == nil) || (hardwareRevision == nil) || (softwareRevision == nil) || (firmwareRevision == nil)) {
                print("[NRFCloud] DIS characteristics status:")
                print("  - Serial Number (2A25): \(serialNumber ?? "MISSING")")
                print("  - Hardware Revision (2A27): \(hardwareRevision ?? "MISSING")")
                print("  - Software Revision (2A28): \(softwareRevision ?? "MISSING")")
                print("  - Firmware Revision (2A26): \(firmwareRevision ?? "MISSING")")
                print("[NRFCloud] Error: At least one required DIS characteristic is missing")
                completion(nil)
                return
            }
            
            let deviceInfo = DeviceInfo(
                deviceId: serialNumber!,
                hardwareVersion: hardwareRevision!,
                softwareType: softwareRevision!,
                appVersion: firmwareRevision!
            )
            
            print("[NRFCloud] Final device info:")
            print("  - Device ID: \(deviceInfo.deviceId)")
            print("  - Hardware Version: \(deviceInfo.hardwareVersion)")
            print("  - Software Type: \(deviceInfo.softwareType)")
            print("  - App Version: \(deviceInfo.appVersion)")
            
            completion(deviceInfo)
        }
    }
    
    private func continueUpdateCheck(with projectKey: String, deviceInfo: DeviceInfo) {
        // Use the local OTA manager instance
        otaManager.checkForUpdate(
            projectKey: projectKey,
            deviceId: deviceInfo.deviceId,
            hardwareVersion: deviceInfo.hardwareVersion,
            softwareType: deviceInfo.softwareType,
            currentVersion: deviceInfo.appVersion,
            extraQuery: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isCheckingForUpdate = false
                self?.checkForUpdatesButton?.isEnabled = true
                
                switch result {
                case .success(let updateInfo):
                    // If we got a success response with update info, an update is available
                    self?.currentMemfaultUpdateInfo = updateInfo  // Store on ImageController
                    self?.updateNRFCloudStatus("Update available!")
                    self?.showUpdateInfo(updateInfo)
                    
                case .failure(let error):
                    // Check for "no update available" error first
                    if let otaError = error as? NRFCloudOTAManager.OTAError,
                       otaError == .noUpdateAvailable {
                        let currentVersion = deviceInfo.appVersion
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
                        if nsError.domain == "NRFCloudOTA" {
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
        // Get update info from ImageController
        guard let updateInfo = currentMemfaultUpdateInfo else {
            updateNRFCloudStatus("No update information available")
            return
        }
        
        guard let downloadUrl = updateInfo.url else {
            updateNRFCloudStatus("Update URL not available")
            return
        }
        
        updateNRFCloudStatus("Downloading update...")
        downloadInstallButton?.isEnabled = false
        
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
                    
                    // Parse and install the firmware package
                    do {
                        let package = try McuMgrPackage(from: destinationURL)
                        self?.updateNRFCloudStatus("Starting installation...")
                        
                        // Get the transport from the base controller
                        guard let baseController = self?.parent as? BaseViewController,
                              let transport = baseController.transport else {
                            self?.updateNRFCloudStatus("Transport not available")
                            self?.downloadInstallButton?.isEnabled = true
                            return
                        }
                        
                        // Create a simple DFU manager and start the upgrade
                        self?.performFirmwareUpgrade(package: package, transport: transport)
                        
                    } catch {
                        self?.updateNRFCloudStatus("Invalid firmware: \(error.localizedDescription)")
                        self?.downloadInstallButton?.isEnabled = true
                    }
                    
                } catch {
                    print("Failed to save firmware: \(error.localizedDescription)")
                    self?.updateNRFCloudStatus("Failed to save firmware: \(error.localizedDescription)")
                    self?.downloadInstallButton?.isEnabled = true
                }
            }
        }
        task.resume()
    }
    
    // MARK: - UI Updates
    
    private func showUpdateInfo(_ updateInfo: NRFCloudOTAManager.UpdateInfo) {
        updateVersionLabel?.text = updateInfo.version ?? "Unknown"
        updateSizeLabel?.text = formatBytes(updateInfo.size ?? 0)
        updateDescriptionLabel?.text = updateInfo.releaseNotes ?? "No description available"
        
        // Show the update rows
        updateInfoCell?.isHidden = false
        actionButtonsCell?.isHidden = false
        
        // Enable the download button
        downloadInstallButton?.isEnabled = true
        
        // Just reload the whole table
        tableView.reloadData()
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Firmware Upgrade
    
    private func performFirmwareUpgrade(package: McuMgrPackage, transport: McuMgrTransport) {
        // Create a DFU configuration with proper estimated swap time
        // This is important for handling disconnection/reconnection during reset
        let configuration = FirmwareUpgradeConfiguration(
            estimatedSwapTime: 15.0,  // Give device 15 seconds to swap and restart
            eraseAppSettings: false,
            pipelineDepth: 1,
            byteAlignment: .disabled,
            upgradeMode: .testAndConfirm  // Use test and confirm mode for safety
        )
        
        // Create and store delegate
        let delegate = SimpleDFUDelegate(imageController: self)
        self.activeDfuDelegate = delegate
        
        // Create DFU manager with the delegate
        let dfuManager = FirmwareUpgradeManager(transport: transport, delegate: delegate)
        dfuManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        
        // Store reference to prevent deallocation
        self.activeDfuManager = dfuManager
        
        // Start the firmware upgrade
        dfuManager.start(package: package, using: configuration)
    }
    
    // MARK: - Helper Properties
    
    // Removed firmwareUpgradeVC property - no longer needed
}

// MARK: - Supporting Types

// MARK: - Simple DFU Delegate

class SimpleDFUDelegate: NSObject, FirmwareUpgradeDelegate {
    weak var imageController: ImageController?
    
    init(imageController: ImageController) {
        self.imageController = imageController
        super.init()
    }
    
    func upgradeDidStart(controller: FirmwareUpgradeController) {
        DispatchQueue.main.async { [weak self] in
            self?.imageController?.updateNRFCloudStatus("Firmware upgrade started...")
        }
    }
    
    func upgradeStateDidChange(from previousState: FirmwareUpgradeState, to newState: FirmwareUpgradeState) {
        DispatchQueue.main.async { [weak self] in
            switch newState {
            case .validate:
                self?.imageController?.updateNRFCloudStatus("Validating firmware...")
            case .upload:
                self?.imageController?.updateNRFCloudStatus("Uploading firmware...")
            case .test:
                self?.imageController?.updateNRFCloudStatus("Testing firmware...")
            case .confirm:
                self?.imageController?.updateNRFCloudStatus("Confirming update...")
            case .reset:
                self?.imageController?.updateNRFCloudStatus("Resetting device...")
            case .success:
                self?.imageController?.updateNRFCloudStatus("Update successful!")
            case .requestMcuMgrParameters:
                self?.imageController?.updateNRFCloudStatus("Requesting parameters...")
            case .bootloaderInfo:
                self?.imageController?.updateNRFCloudStatus("Getting bootloader info...")
            case .eraseAppSettings:
                self?.imageController?.updateNRFCloudStatus("Erasing app settings...")
            case .none:
                break
            }
        }
    }
    
    func upgradeDidComplete() {
        DispatchQueue.main.async { [weak self] in
            self?.imageController?.updateNRFCloudStatus("Update completed successfully!")
            self?.imageController?.downloadInstallButton?.isEnabled = true
            self?.imageController?.hideUpdateRows()
            self?.imageController?.activeDfuManager = nil
            self?.imageController?.activeDfuDelegate = nil
        }
    }
    
    func upgradeDidFail(inState state: FirmwareUpgradeState, with error: Error) {
        DispatchQueue.main.async { [weak self] in
            // Check the specific error type
            let errorDescription = error.localizedDescription.lowercased()
            
            // Don't clear the DFU manager for temporary disconnections during reset
            if state == .reset && (errorDescription.contains("disconnect") || 
                                  errorDescription.contains("connection")) {
                self?.imageController?.updateNRFCloudStatus("Device resetting... waiting for reconnection")
                // Don't clear the DFU manager or delegate - let it handle reconnection
                return
            }
            
            // For other disconnection errors
            if errorDescription.contains("disconnect") || 
               errorDescription.contains("connection") ||
               errorDescription.contains("timeout") {
                self?.imageController?.updateNRFCloudStatus("Connection lost. Reconnect to resume.")
            } else {
                self?.imageController?.updateNRFCloudStatus("Update failed: \(error.localizedDescription)")
            }
            
            // Clear references only for non-recoverable errors
            self?.imageController?.downloadInstallButton?.isEnabled = true
            self?.imageController?.activeDfuManager = nil
            self?.imageController?.activeDfuDelegate = nil
        }
    }
    
    func upgradeDidCancel(state: FirmwareUpgradeState) {
        DispatchQueue.main.async { [weak self] in
            self?.imageController?.updateNRFCloudStatus("Update cancelled")
            self?.imageController?.downloadInstallButton?.isEnabled = true
            self?.imageController?.activeDfuManager = nil
            self?.imageController?.activeDfuDelegate = nil
        }
    }
    
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        DispatchQueue.main.async { [weak self] in
            let percentage = Int((Float(bytesSent) / Float(imageSize)) * 100)
            self?.imageController?.updateNRFCloudStatus("Installing: \(percentage)%")
        }
    }
}

