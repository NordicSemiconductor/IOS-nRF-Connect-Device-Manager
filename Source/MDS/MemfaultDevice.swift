/*
 * Copyright (c) 2025 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

/// Represents a Bluetooth device with Memfault MDS capabilities
public class MemfaultDevice {
    
    public let deviceUUID: String
    public let peripheral: CBPeripheral
    
    public var isConnected: Bool = false
    public var isNotificationEnabled: Bool = false
    public var isStreamingData: Bool = false
    public var chunks: [MemfaultChunk] = []
    
    // MDS Service characteristics
    public var mdsService: CBService?
    internal var deviceIdentifierCharacteristic: CBCharacteristic?
    internal var dataURICharacteristic: CBCharacteristic?
    internal var authenticationCharacteristic: CBCharacteristic?
    public var dataExportCharacteristic: CBCharacteristic?
    
    // DIS Service characteristics
    public var disService: CBService?
    internal var manufacturerNameCharacteristic: CBCharacteristic?
    internal var modelNumberCharacteristic: CBCharacteristic?
    internal var hardwareRevisionCharacteristic: CBCharacteristic?
    internal var firmwareRevisionCharacteristic: CBCharacteristic?
    internal var softwareRevisionCharacteristic: CBCharacteristic?
    
    // Device info from MDS
    public var deviceIdentifier: String?
    public var dataURI: String?
    public var authenticationData: Data?
    public var projectKey: String?
    
    // Device info from DIS
    public var manufacturerName: String?
    public var modelNumber: String?
    public var hardwareRevision: String?
    public var firmwareRevision: String?
    public var softwareRevision: String?
    
    public init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.deviceUUID = peripheral.identifier.uuidString
    }
    
    // MARK: - Chunk Management
    
    public func addChunk(_ chunk: MemfaultChunk) {
        chunks.append(chunk)
    }
    
    public func removeChunk(_ chunk: MemfaultChunk) {
        chunks.removeAll { $0.id == chunk.id }
    }
    
    public func clearChunks() {
        chunks.removeAll()
    }
    
    public var pendingChunks: [MemfaultChunk] {
        return chunks.filter { $0.isReadyForUpload }
    }
    
    // MARK: - MDS Support
    
    public var hasMDSService: Bool {
        return mdsService != nil
    }
    
    public var hasAllCharacteristics: Bool {
        return deviceIdentifierCharacteristic != nil &&
               dataURICharacteristic != nil &&
               authenticationCharacteristic != nil &&
               dataExportCharacteristic != nil
    }
    
    // MARK: - Memfault OTA Support
    
    /// Derive hardware version for Memfault API from DIS data
    public var memfaultHardwareVersion: String {
        // Try to derive from model number or hardware revision
        if let modelNumber = modelNumber?.lowercased() {
            // Extract nRF chip type from model number (e.g., "nRF52840_xxAA" -> "nrf52")
            if modelNumber.contains("nrf52") {
                return "nrf52"
            } else if modelNumber.contains("nrf53") {
                return "nrf53"
            } else if modelNumber.contains("nrf54") {
                return "nrf54"
            } else if modelNumber.contains("nrf91") {
                return "nrf91"
            }
        }
        
        if let hardwareRevision = hardwareRevision?.lowercased() {
            // Try to extract from hardware revision
            if hardwareRevision.contains("nrf52") {
                return "nrf52"
            } else if hardwareRevision.contains("nrf53") {
                return "nrf53"
            } else if hardwareRevision.contains("nrf54") {
                return "nrf54"
            } else if hardwareRevision.contains("nrf91") {
                return "nrf91"
            }
        }
        
        // Default fallback
        return "nrf53"
    }
    
    /// Derive software type for Memfault API from DIS/MDS data
    public var memfaultSoftwareType: String {
        // Try to derive from firmware or software revision
        if let softwareRevision = softwareRevision?.lowercased() {
            // Look for common software type indicators
            if softwareRevision.contains("bootloader") || softwareRevision.contains("mcuboot") {
                return "bootloader"
            } else if softwareRevision.contains("application") || softwareRevision.contains("app") {
                return "application"
            }
        }
        
        if let firmwareRevision = firmwareRevision?.lowercased() {
            if firmwareRevision.contains("bootloader") || firmwareRevision.contains("mcuboot") {
                return "bootloader"
            } else if firmwareRevision.contains("application") || firmwareRevision.contains("app") {
                return "application"
            }
        }
        
        // Default to "main" (common for application firmware)
        return "main"
    }
}