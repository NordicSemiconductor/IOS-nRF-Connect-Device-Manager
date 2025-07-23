//
//  McuMgrBleTransport+CBPeripheralDelegate.swift
//  McuManager
//
//  Created by Dinesh Harjani on 4/5/22.
//

import Foundation
import CoreBluetooth
import OSLog

// MARK: - McuMgrBleTransport+CBPeripheralDelegate

extension McuMgrBleTransport: CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Check for error.
        guard error == nil else {
            connectionLock.open(error)
            return
        }
        
        let s = peripheral.services?
            .map({ $0.uuid.uuidString })
            .joined(separator: ", ")
            ?? "none"
        log(msg: "Services discovered: \(s)", atLevel: .verbose)
        
        // Check if MDS service is present (might require pairing)
        let hasMDS = peripheral.services?.contains { $0.uuid.uuidString == "54220000-F6A5-4007-A371-722F4EBD8436" } ?? false
        if !hasMDS {
            log(msg: "MDS service not found - it may require pairing/bonding", atLevel: .info)
        }
        
        // Get peripheral's services.
        guard let services = peripheral.services else {
            connectionLock.open(McuMgrBleTransportError.missingService)
            return
        }
        
        var smpServiceFound = false
        
        // Find the service matching the SMP service UUID.
        for service in services {
            if service.uuid == McuMgrBleTransportConstant.SMP_SERVICE {
                log(msg: "Discovering SMP characteristics...", atLevel: .verbose)
                peripheral.discoverCharacteristics([McuMgrBleTransportConstant.SMP_CHARACTERISTIC],
                                                   for: service)
                smpServiceFound = true
            } else if service.uuid.uuidString == "54220000-F6A5-4007-A371-722F4EBD8436" {
                // MDS Service - discover its characteristics for Memfault functionality
                log(msg: "Discovering MDS characteristics...", atLevel: .verbose)
                log(msg: "Note: MDS access may trigger pairing/PIN entry dialog", atLevel: .info)
                discoveredMDSService = service
                let mdsCharacteristics = [
                    CBUUID(string: "54220001-F6A5-4007-A371-722F4EBD8436"), // Supported Features
                    CBUUID(string: "54220002-F6A5-4007-A371-722F4EBD8436"), // Device Identifier
                    CBUUID(string: "54220003-F6A5-4007-A371-722F4EBD8436"), // Data URI
                    CBUUID(string: "54220004-F6A5-4007-A371-722F4EBD8436"), // Authorization (contains project key!)
                    CBUUID(string: "54220005-F6A5-4007-A371-722F4EBD8436")  // Data Export
                ]
                peripheral.discoverCharacteristics(mdsCharacteristics, for: service)
            } else if service.uuid.uuidString == "180A" {
                // DIS Service - discover its characteristics for device information
                log(msg: "Discovering DIS characteristics...", atLevel: .verbose)
                discoveredDISService = service
                let disCharacteristics = [
                    CBUUID(string: "2A29"), // Manufacturer Name
                    CBUUID(string: "2A24"), // Model Number
                    CBUUID(string: "2A27"), // Hardware Revision
                    CBUUID(string: "2A26"), // Firmware Revision
                    CBUUID(string: "2A28")  // Software Revision
                ]
                peripheral.discoverCharacteristics(disCharacteristics, for: service)
            }
        }
        
        if !smpServiceFound {
            connectionLock.open(McuMgrBleTransportError.missingService)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        // Check for error.
        guard error == nil else {
            log(msg: "Error discovering characteristics for \(service.uuid): \(error!)", atLevel: .error)
            // Check if this is an authentication error for MDS
            if service.uuid.uuidString == "54220000-F6A5-4007-A371-722F4EBD8436" {
                log(msg: "MDS characteristic discovery failed - pairing may be required", atLevel: .warning)
            }
            if service.uuid == McuMgrBleTransportConstant.SMP_SERVICE {
                connectionLock.open(error)
            }
            return
        }
        
        let c = service.characteristics?
            .map({ $0.uuid.uuidString })
            .joined(separator: ", ")
            ?? "none"
        log(msg: "Characteristics discovered: \(c)", atLevel: .verbose)
        
        // Get service's characteristics.
        guard let characteristics = service.characteristics else {
            if service.uuid == McuMgrBleTransportConstant.SMP_SERVICE {
                connectionLock.open(McuMgrBleTransportError.missingCharacteristic)
            }
            return
        }
        
        if service.uuid == McuMgrBleTransportConstant.SMP_SERVICE {
            // Find the characteristic matching the SMP characteristic UUID.
            for characteristic in characteristics {
                if characteristic.uuid == McuMgrBleTransportConstant.SMP_CHARACTERISTIC {
                    // Set the characteristic notification if available.
                    if characteristic.properties.contains(.notify) {
                        log(msg: "Enabling notifications...", atLevel: .verbose)
                        peripheral.setNotifyValue(true, for: characteristic)
                    } else {
                        connectionLock.open(McuMgrBleTransportError.missingNotifyProperty)
                    }
                    return
                }
            }
            connectionLock.open(McuMgrBleTransportError.missingCharacteristic)
        } else if service.uuid.uuidString == "54220000-F6A5-4007-A371-722F4EBD8436" {
            // MDS Service characteristics discovered
            log(msg: "MDS characteristics discovered: \(characteristics.count)", atLevel: .info)
            for (index, char) in characteristics.enumerated() {
                log(msg: "  MDS Char \(index): \(char.uuid.uuidString) - Properties: \(char.properties)", atLevel: .info)
            }
            discoveredMDSCharacteristics = characteristics
            
            // Try to read the authorization characteristic - this may trigger pairing
            if let authChar = characteristics.first(where: { $0.uuid.uuidString == "54220004-F6A5-4007-A371-722F4EBD8436" }) {
                log(msg: "Reading MDS Authorization - this may trigger pairing dialog", atLevel: .info)
                peripheral.readValue(for: authChar)
            }
            
            // Enable notifications for data export characteristic
            if let dataExportChar = characteristics.first(where: { $0.uuid.uuidString == "54220005-F6A5-4007-A371-722F4EBD8436" }) {
                log(msg: "Found MDS Data Export characteristic. Properties: \(dataExportChar.properties.rawValue)", atLevel: .info)
                
                // Check if there's already data available
                if let existingData = dataExportChar.value, existingData.count > 0 {
                    log(msg: "*** MDS DATA EXPORT HAS EXISTING DATA ***", atLevel: .info)
                    log(msg: "Data size: \(existingData.count) bytes", atLevel: .info)
                    log(msg: "First 10 bytes: \(existingData.prefix(10).map { String(format: "%02x", $0) }.joined(separator: " "))", atLevel: .info)
                    
                    // Delay processing to allow MemfaultManager to connect first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak peripheral] in
                        guard let peripheral = peripheral else { return }
                        self.log(msg: "Processing delayed MDS data export", atLevel: .info)
                        NotificationCenter.default.post(
                            name: Notification.Name("MDSDataExportNotification"),
                            object: nil,
                            userInfo: ["data": existingData, "peripheral": peripheral]
                        )
                    }
                }
                
                if dataExportChar.properties.contains(.notify) {
                    log(msg: "MDS Data Export supports notifications. Enabling...", atLevel: .info)
                    peripheral.setNotifyValue(true, for: dataExportChar)
                } else if dataExportChar.properties.contains(.indicate) {
                    log(msg: "MDS Data Export supports indications. Enabling...", atLevel: .info)
                    peripheral.setNotifyValue(true, for: dataExportChar)
                } else {
                    log(msg: "MDS Data Export characteristic does not support notifications or indications. Properties: \(dataExportChar.properties)", atLevel: .error)
                }
            } else {
                log(msg: "MDS Data Export characteristic not found among \(characteristics.count) characteristics", atLevel: .warning)
            }
        } else if service.uuid.uuidString == "180A" {
            // DIS Service characteristics discovered
            log(msg: "DIS characteristics discovered: \(characteristics.count)", atLevel: .verbose)
            discoveredDISCharacteristics = characteristics
            
            // Automatically read DIS characteristic values
            for characteristic in characteristics {
                peripheral.readValue(for: characteristic)
                log(msg: "Reading DIS characteristic: \(characteristic.uuid)", atLevel: .verbose)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        // Handle MDS Data Export notification state changes
        if characteristic.uuid.uuidString == "54220005-F6A5-4007-A371-722F4EBD8436" {
            if let error = error {
                log(msg: "ERROR: Failed to enable MDS Data Export notifications: \(error)", atLevel: .error)
                log(msg: "Error details: \(error.localizedDescription)", atLevel: .error)
            } else {
                log(msg: "SUCCESS: MDS Data Export notifications are now \(characteristic.isNotifying ? "ENABLED" : "DISABLED")", atLevel: .info)
                if characteristic.isNotifying {
                    log(msg: "Ready to receive MDS diagnostic data chunks", atLevel: .info)
                }
            }
            return
        }
        
        guard characteristic.uuid == McuMgrBleTransportConstant.SMP_CHARACTERISTIC else {
            return
        }
        // Check for error.
        guard error == nil else {
            connectionLock.open(error)
            return
        }
        
        log(msg: "Notifications enabled", atLevel: .verbose)
        
        // Set the SMP characteristic.
        smpCharacteristic = characteristic
        state = .connected
        notifyStateChanged(.connected)
        
        // The SMP Service and characteristic have now been discovered and set
        // up. Signal the dispatch semaphore to continue to send the request.
        connectionLock.open(key: McuMgrBleTransportKey.discoveringSmpCharacteristic.rawValue)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        // Handle DIS characteristic value updates
        if characteristic.service?.uuid.uuidString == "180A" {
            if let error = error {
                log(msg: "Error reading DIS characteristic \(characteristic.uuid): \(error)", atLevel: .warning)
            } else if let value = characteristic.value {
                if let stringValue = String(data: value, encoding: .utf8) {
                    log(msg: "DIS characteristic \(characteristic.uuid) value: \(stringValue)", atLevel: .verbose)
                }
                
                // Post notification for DIS value updates
                NotificationCenter.default.post(
                    name: Notification.Name("DISValueUpdated"),
                    object: nil,
                    userInfo: [
                        "uuid": characteristic.uuid.uuidString,
                        "value": value
                    ]
                )
            }
            return
        }
        
        // Handle MDS characteristic value updates
        if characteristic.service?.uuid.uuidString == "54220000-F6A5-4007-A371-722F4EBD8436" {
            if let error = error {
                log(msg: "Error reading MDS characteristic \(characteristic.uuid): \(error)", atLevel: .warning)
                if (error as NSError).code == 5 || (error as NSError).code == 15 {
                    log(msg: "MDS read failed due to insufficient authentication - pairing required", atLevel: .warning)
                }
            } else if let value = characteristic.value {
                // Handle data export notifications
                if characteristic.uuid.uuidString == "54220005-F6A5-4007-A371-722F4EBD8436" {
                    log(msg: "*** MDS DATA EXPORT NOTIFICATION RECEIVED ***", atLevel: .info)
                    log(msg: "Data size: \(value.count) bytes", atLevel: .info)
                    log(msg: "Data hex: \(value.map { String(format: "%02x", $0) }.joined())", atLevel: .info)
                    log(msg: "First 10 bytes: \(value.prefix(10).map { String(format: "%02x", $0) }.joined(separator: " "))", atLevel: .info)
                    
                    // Forward the data to MemfaultManager if it's connected
                    log(msg: "Posting notification to MemfaultManager", atLevel: .info)
                    NotificationCenter.default.post(
                        name: Notification.Name("MDSDataExportNotification"),
                        object: nil,
                        userInfo: ["data": value, "peripheral": peripheral]
                    )
                } else {
                    log(msg: "MDS characteristic \(characteristic.uuid) read successfully", atLevel: .info)
                    if let stringValue = String(data: value, encoding: .utf8) {
                        log(msg: "MDS value: \(stringValue)", atLevel: .verbose)
                    }
                }
            }
            return
        }
        
        guard characteristic.uuid == McuMgrBleTransportConstant.SMP_CHARACTERISTIC else {
            return
        }
        
        if let error = error {
            writeState.onError(error)
            return
        }
        
        // Assumption: CoreBluetooth is delivering all packets from the same sender,
        // in order.
        guard let data = characteristic.value else {
            writeState.onError(McuMgrTransportError.badResponse)
            return
        }
        
        // Check that we've received all the data for the Sequence Number of the
        // previous received Data.
        if let previousUpdateNotificationSequenceNumber = previousUpdateNotificationSequenceNumber,
           !writeState.isChunkComplete(for: previousUpdateNotificationSequenceNumber) {
            
            // Add Data to the previous Sequence Number.
            writeState.received(sequenceNumber: previousUpdateNotificationSequenceNumber, data: data)
            return
        }
        
        // If the Data is the first 'chunk', it will include the header.
        guard let sequenceNumber = data.readMcuMgrHeaderSequenceNumber() else {
            writeState.onError(McuMgrTransportError.badResponse)
            return
        }
        
        previousUpdateNotificationSequenceNumber = sequenceNumber
        writeState.received(sequenceNumber: sequenceNumber, data: data)
    }
    
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        // Restart any paused writes due to Peripheral not being ready for more writes.
        writeState.sharedLock { [unowned self] in
            guard !pausedWrites.isEmpty else { return }
            for pausedWrite in pausedWrites {
                log(msg: "► [Seq: \(pausedWrite.sequenceNumber)] Resume (Peripheral Ready for Write Without Response)", atLevel: .debug)
                coordinatedWrite(of: pausedWrite.sequenceNumber, data: Array(pausedWrite.remaining), to: pausedWrite.peripheral, characteristic: pausedWrite.characteristic, callback: pausedWrite.callback)
            }
            pausedWrites.removeAll()
        }
    }
}
