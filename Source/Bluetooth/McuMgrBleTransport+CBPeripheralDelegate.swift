//
//  McuMgrBleTransport+CBPeripheralDelegate.swift
//  McuManager
//
//  Created by Dinesh Harjani on 4/5/22.
//

import Foundation
import CoreBluetooth

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
        
        // Get peripheral's services.
        guard let services = peripheral.services else {
            connectionLock.open(McuMgrBleTransportError.missingService)
            return
        }
        // Find the service matching the SMP service UUID.
        for service in services {
            if service.uuid == McuMgrBleTransportConstant.SMP_SERVICE {
                log(msg: "Discovering characteristics...", atLevel: .verbose)
                peripheral.discoverCharacteristics([McuMgrBleTransportConstant.SMP_CHARACTERISTIC],
                                                   for: service)
                return
            }
        }
        connectionLock.open(McuMgrBleTransportError.missingService)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        // Check for error.
        guard error == nil else {
            connectionLock.open(error)
            return
        }
        
        let c = service.characteristics?
            .map({ $0.uuid.uuidString })
            .joined(separator: ", ")
            ?? "none"
        log(msg: "Characteristics discovered: \(c)", atLevel: .verbose)
        
        // Get service's characteristics.
        guard let characteristics = service.characteristics else {
            connectionLock.open(McuMgrBleTransportError.missingCharacteristic)
            return
        }
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
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
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
        
        // The SMP Service and characateristic have now been discovered and set
        // up. Signal the dispatch semaphore to continue to send the request.
        connectionLock.open(key: McuMgrBleTransportKey.discoveringSmpCharacteristic.rawValue)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard characteristic.uuid == McuMgrBleTransportConstant.SMP_CHARACTERISTIC else {
            return
        }
        
        guard error == nil else {
            writeLocks.values.forEach {
                $0.open(error)
            }
            return
        }
        
        guard let data = characteristic.value else {
            writeLocks.values.forEach {
                $0.open(McuMgrTransportError.badResponse)
            }
            return
        }
        
        guard let sequenceNumber = data.readMcuMgrHeaderSequenceNumber() else {
            writeLocks.values.forEach {
                $0.open(McuMgrTransportError.badHeader)
            }
            return
        }
        
        // Get the expected length from the response data.
        if writeState[sequenceNumber] == nil {
            // If we do not have any current response data, this is the initial
            // packet in a potentially fragmented response. Get the expected
            // length of the full response and initialize the responseData with
            // the expected capacity.
            guard let dataSize = McuMgrResponse.getExpectedLength(scheme: .ble, responseData: data) else {
                writeLocks[sequenceNumber]?.open(McuMgrTransportError.badResponse)
                return
            }
            writeState[sequenceNumber] = (Data(capacity: dataSize), dataSize)
        }
                
        // Append the response data.
        writeState[sequenceNumber]?.chunk.append(data)
        
        // If we have recevied all the bytes, signal the waiting lock.
        guard let chunkSize = writeState[sequenceNumber]?.chunk.count,
              let expectedChunkSize = writeState[sequenceNumber]?.totalChunkSize,
              chunkSize >= expectedChunkSize else { return }
        
        writeLocks[sequenceNumber]?.open()
    }
}
