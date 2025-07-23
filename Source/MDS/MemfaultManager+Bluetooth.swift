/*
 * Copyright (c) 2025 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

// MARK: - CBPeripheralDelegate

extension MemfaultManager: CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            print("MemfaultManager: Error discovering services: \(error!)")
            onError?(.mdsServiceNotFound)
            return
        }
        
        guard let services = peripheral.services else {
            onError?(.mdsServiceNotFound)
            return
        }
        
        // Look for MDS service
        if let mdsService = services.first(where: { $0.uuid == .mdsService }) {
            print("MemfaultManager: Found MDS service")
            connectedDevice?.mdsService = mdsService
            
            // Discover MDS characteristics
            peripheral.discoverCharacteristics([
                .mdsSupportedFeatures,
                .mdsDeviceIdentifier,
                .mdsDataURI,
                .mdsAuthorization,
                .mdsDataExport
            ], for: mdsService)
        } else {
            print("MemfaultManager: MDS service not found")
        }
        
        // Look for DIS service (always useful for device info)
        if let disService = services.first(where: { $0.uuid == .deviceInformationService }) {
            print("MemfaultManager: Found DIS service")
            connectedDevice?.disService = disService
            
            // Discover DIS characteristics
            peripheral.discoverCharacteristics([
                .manufacturerNameString,
                .modelNumberString,
                .hardwareRevisionString,
                .firmwareRevisionString,
                .softwareRevisionString
            ], for: disService)
        } else {
            print("MemfaultManager: DIS service not found")
        }
        
        // If neither service is found, consider it an error
        if connectedDevice?.mdsService == nil && connectedDevice?.disService == nil {
            onError?(.mdsServiceNotFound)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, 
                          didDiscoverCharacteristicsFor service: CBService, 
                          error: Error?) {
        guard error == nil else {
            print("MemfaultManager: Error discovering characteristics: \(error!)")
            return
        }
        
        guard let device = connectedDevice,
              let characteristics = service.characteristics else { return }
        
        if service.uuid == .mdsService {
            print("MemfaultManager: Discovered \(characteristics.count) MDS characteristics")
            
            // Map MDS characteristics
            for characteristic in characteristics {
                switch characteristic.uuid {
                case .mdsSupportedFeatures:
                    // We don't need to store this characteristic for now
                    peripheral.readValue(for: characteristic)
                    
                case .mdsDeviceIdentifier:
                    device.deviceIdentifierCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    
                case .mdsDataURI:
                    device.dataURICharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    
                case .mdsAuthorization:
                    device.authenticationCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    
                case .mdsDataExport:
                    device.dataExportCharacteristic = characteristic
                    // This will be used for notifications
                    
                default:
                    break
                }
            }
            
            // Check if we have all required MDS characteristics
            if device.hasAllCharacteristics {
                print("MemfaultManager: All MDS characteristics found")
                device.isConnected = true
                onDeviceConnected?(device)
            }
            
        } else if service.uuid == .deviceInformationService {
            print("MemfaultManager: Discovered \(characteristics.count) DIS characteristics")
            
            // Map DIS characteristics and read their values
            for characteristic in characteristics {
                switch characteristic.uuid {
                case .manufacturerNameString:
                    device.manufacturerNameCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    
                case .modelNumberString:
                    device.modelNumberCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    
                case .hardwareRevisionString:
                    device.hardwareRevisionCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    
                case .firmwareRevisionString:
                    device.firmwareRevisionCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    
                case .softwareRevisionString:
                    device.softwareRevisionCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    
                default:
                    break
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, 
                          didUpdateValueFor characteristic: CBCharacteristic, 
                          error: Error?) {
        guard error == nil,
              let device = connectedDevice else {
            if let error = error {
                print("MemfaultManager: Error reading characteristic: \(error)")
            }
            return
        }
        
        // Handle case where characteristic value is nil or empty
        guard let data = characteristic.value, !data.isEmpty else {
            // Special handling for MDS Data Export - empty means no more chunks
            if characteristic.uuid == .mdsDataExport {
                print("MemfaultManager: No more chunks available in MDS Data Export")
            }
            return
        }
        
        print("MemfaultManager: Received value for characteristic \(characteristic.uuid.uuidString)")
        if let stringValue = String(data: data, encoding: .utf8) {
            print("MemfaultManager: String value for \(characteristic.uuid.uuidString): '\(stringValue)'")
        }
        
        // Print hex value for debugging
        print("MemfaultManager: Hex value: \(data.map { String(format: "%02x", $0) }.joined())")
        
        switch characteristic.uuid {
        // MDS characteristics
        case .mdsSupportedFeatures:
            // Just log the supported features
            if let stringValue = String(data: data, encoding: .utf8) {
                print("MemfaultManager: Supported features: '\(stringValue)'")
            }
            
        case .mdsDeviceIdentifier:
            handleDeviceIdentifierUpdate(data, device: device)
            
        case .mdsDataURI:
            handleDataURIUpdate(data, device: device)
            
        case .mdsAuthorization:
            handleAuthenticationUpdate(data, device: device)
            
        case .mdsDataExport:
            handleDataExportUpdate(data, device: device)
            
        // DIS characteristics
        case .manufacturerNameString:
            handleManufacturerNameUpdate(data, device: device)
            
        case .modelNumberString:
            handleModelNumberUpdate(data, device: device)
            
        case .hardwareRevisionString:
            handleHardwareRevisionUpdate(data, device: device)
            
        case .firmwareRevisionString:
            handleFirmwareRevisionUpdate(data, device: device)
            
        case .softwareRevisionString:
            handleSoftwareRevisionUpdate(data, device: device)
            
        default:
            break
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, 
                          didUpdateNotificationStateFor characteristic: CBCharacteristic, 
                          error: Error?) {
        guard error == nil,
              let device = connectedDevice else {
            if let error = error {
                print("MemfaultManager: Error setting notification state: \(error)")
                onError?(.notificationSetupFailed)
            }
            return
        }
        
        if characteristic.uuid == .mdsDataExport {
            device.isNotificationEnabled = characteristic.isNotifying
            device.isStreamingData = characteristic.isNotifying
            print("MemfaultManager: Data export notifications \(characteristic.isNotifying ? "enabled" : "disabled")")
        }
    }
    
    // MARK: - Characteristic Update Handlers
    
    private func handleDeviceIdentifierUpdate(_ data: Data, device: MemfaultDevice) {
        guard let identifier = String(data: data, encoding: .utf8) else {
            onError?(.deviceIdentifierReadFailed)
            return
        }
        
        device.deviceIdentifier = identifier
        print("MemfaultManager: Device identifier: '\(identifier)'")
        
        // Check if this might contain project key info
        if identifier.contains("project_key=") {
            extractProjectKey(from: identifier, device: device)
        } else if identifier.hasPrefix("Memfault-Project-Key:") {
            let prefix = "Memfault-Project-Key:"
            let projectKey = identifier.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces)
            if !projectKey.isEmpty {
                device.projectKey = projectKey
                print("MemfaultManager: Extracted project key from device ID: \(projectKey)")
                onDeviceInfoUpdated?(device)
            }
        }
    }
    
    private func handleDataURIUpdate(_ data: Data, device: MemfaultDevice) {
        guard let uri = String(data: data, encoding: .utf8) else {
            print("MemfaultManager: Failed to parse Data URI from data: \(data.map { String(format: "%02x", $0) }.joined())")
            onError?(.dataURIReadFailed)
            return
        }
        
        device.dataURI = uri
        print("MemfaultManager: Data URI received: '\(uri)'")
        print("MemfaultManager: Data URI length: \(uri.count) characters")
        
        // If URI contains a project key, extract it
        if uri.contains("project_key=") {
            print("MemfaultManager: Data URI contains project_key parameter")
            extractProjectKey(from: uri, device: device)
        } else {
            print("MemfaultManager: Data URI does not contain project_key parameter")
        }
        
        // The project key might be in the authentication data or needs to be configured separately
        // For now, notify that device info is updated
        onDeviceInfoUpdated?(device)
    }
    
    private func handleAuthenticationUpdate(_ data: Data, device: MemfaultDevice) {
        device.authenticationData = data
        print("MemfaultManager: Authentication data received (\(data.count) bytes)")
        
        // Extract project key from authentication data
        if let authString = String(data: data, encoding: .utf8) {
            print("MemfaultManager: Authentication string: '\(authString)'")
            
            // Try to extract project key - it might be in different formats
            // Format 1: "Memfault-Project-Key:<key>"
            // Format 2: Just the key itself
            // Format 3: Part of a URL query parameter
            
            let prefix = "Memfault-Project-Key:"
            if authString.hasPrefix(prefix) {
                let projectKey = authString.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces)
                if !projectKey.isEmpty {
                    device.projectKey = projectKey
                    print("MemfaultManager: Extracted project key from header format: \(projectKey)")
                    print("MemfaultManager: Calling onDeviceInfoUpdated callback")
                    onDeviceInfoUpdated?(device)
                }
            } else if authString.contains("project_key=") {
                // Try to extract from URL format
                extractProjectKey(from: authString, device: device)
            } else if !authString.isEmpty && !authString.contains("http") && !authString.contains("/") {
                // Might be just the key itself
                let trimmedKey = authString.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedKey.count >= 20 { // Project keys are typically long
                    device.projectKey = trimmedKey
                    print("MemfaultManager: Using authentication value as project key: \(trimmedKey)")
                    onDeviceInfoUpdated?(device)
                }
            }
        }
    }
    
    internal func handleDataExportUpdate(_ data: Data, device: MemfaultDevice) {
        print("MemfaultManager: Processing data export update: \(data.count) bytes")
        print("MemfaultManager: Data hex: \(data.map { String(format: "%02x", $0) }.joined())")
        
        guard let chunk = parseChunkData(data) else {
            print("MemfaultManager: Failed to parse chunk data")
            onError?(.chunkDataInvalid)
            return
        }
        
        print("MemfaultManager: Received chunk \(chunk.sequenceNumber) (\(chunk.data.count) bytes)")
        device.addChunk(chunk)
        onChunkReceived?(chunk)
        
        // Auto-upload chunks if we have a project key
        if device.projectKey != nil && device.pendingChunks.count >= 1 {
            print("MemfaultManager: Auto-uploading \(device.pendingChunks.count) chunks")
            uploadPendingChunks()
        }
        
        // No acknowledgment needed - MDS uses continuous notifications
        // The device will send all chunks via notifications once streaming is enabled
    }
    
    private func extractProjectKey(from uri: String, device: MemfaultDevice) {
        // Parse the URI to extract project key
        // Expected format: https://api.memfault.com/api/v0/chunks?project_key=<key>
        
        guard let url = URL(string: uri),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("MemfaultManager: Could not parse data URI")
            return
        }
        
        if let projectKeyItem = queryItems.first(where: { $0.name == "project_key" }),
           let projectKey = projectKeyItem.value {
            device.projectKey = projectKey
            print("MemfaultManager: Extracted project key: \(projectKey)")
            // Notify that device info has been updated (including project key)
            onDeviceInfoUpdated?(device)
        }
    }
    
    // MARK: - DIS Characteristic Update Handlers
    
    internal func handleManufacturerNameUpdate(_ data: Data, device: MemfaultDevice) {
        guard let manufacturerName = String(data: data, encoding: .utf8) else {
            print("MemfaultManager: Failed to parse manufacturer name")
            return
        }
        
        device.manufacturerName = manufacturerName
        print("MemfaultManager: Manufacturer name: \(manufacturerName)")
        // Don't call onDeviceInfoUpdated here - wait until all values are read
    }
    
    internal func handleModelNumberUpdate(_ data: Data, device: MemfaultDevice) {
        guard let modelNumber = String(data: data, encoding: .utf8) else {
            print("MemfaultManager: Failed to parse model number")
            return
        }
        
        device.modelNumber = modelNumber
        print("MemfaultManager: Model number: \(modelNumber)")
        // Don't call onDeviceInfoUpdated here - wait until all values are read
    }
    
    internal func handleHardwareRevisionUpdate(_ data: Data, device: MemfaultDevice) {
        guard let hardwareRevision = String(data: data, encoding: .utf8) else {
            print("MemfaultManager: Failed to parse hardware revision")
            return
        }
        
        device.hardwareRevision = hardwareRevision
        print("MemfaultManager: Hardware revision: \(hardwareRevision)")
        // Don't call onDeviceInfoUpdated here - wait until all values are read
    }
    
    internal func handleFirmwareRevisionUpdate(_ data: Data, device: MemfaultDevice) {
        guard let firmwareRevision = String(data: data, encoding: .utf8) else {
            print("MemfaultManager: Failed to parse firmware revision")
            return
        }
        
        device.firmwareRevision = firmwareRevision
        print("MemfaultManager: Firmware revision: \(firmwareRevision)")
        // Don't call onDeviceInfoUpdated here - wait until all values are read
    }
    
    internal func handleSoftwareRevisionUpdate(_ data: Data, device: MemfaultDevice) {
        guard let softwareRevision = String(data: data, encoding: .utf8) else {
            print("MemfaultManager: Failed to parse software revision")
            return
        }
        
        device.softwareRevision = softwareRevision
        print("MemfaultManager: Software revision: \(softwareRevision)")
        // Don't call onDeviceInfoUpdated here - wait until all values are read
    }
}