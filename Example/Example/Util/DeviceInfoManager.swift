//
//  DeviceInfoManager.swift
//  iOSOtaLibrary
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 3/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import iOSOtaLibrary
import iOS_BLE_Library_Mock

// MARK: - DeviceInfoManager

/**
 Migrated code, originally part of ``iOSMcuManagerLibrary`` API for Over-The-Air (OTA) update functionality.
 
 It is presently unclear what the officially-supported method for obtaining ``DeviceInfoToken`` and ``ProjectKey`` values will be. So for the moment, the recommended solution [as per Memfault Documentation](https://docs.memfault.com/docs/mcu/nordic-nrf-connect-sdk-guide) is implemented here. You may copy it and adapt it to your liking. It is part of the public repository of nRF Connect Device Manager, after all.
 */
final class DeviceInfoManager {
    
    // MARK: Properties
    
    internal let peripheralUUID: UUID
    internal var ble = CentralManager()
    
    // MARK: init
    
    init(_ peripheralUUID: UUID) {
        self.peripheralUUID = peripheralUUID
    }
}

// MARK: - DeviceInfoManagerError

public enum DeviceInfoManagerError: LocalizedError {
    case bleUnavailable
    case peripheralNotFound
    case serviceNotFound
    case incompleteDeviceInfo
    case mdsKeyDecodeError
}

// MARK: - getDeviceInfoToken

extension DeviceInfoManager {
    
    /**
     Callback-based wrapper for async ``getDeviceInfoToken()`` API.
     */
    func getDeviceInfoToken(_ callback: @escaping (Result<DeviceInfoToken, DeviceInfoManagerError>) -> ()) {
        Task { @MainActor in
            do {
                let token = try await getDeviceInfoToken()
                callback(.success(token))
            } catch {
                guard let otaError = error as? DeviceInfoManagerError else {
                    callback(.failure(.incompleteDeviceInfo))
                    return
                }
                callback(.failure(otaError))
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    /**
     Reads ``DeviceInfoToken`` from the Peripheral's 180A or GATT Device Information Service.
     */
    func getDeviceInfoToken() async throws -> DeviceInfoToken {
        do {
            try await ble.isPoweredOn()
            
            guard let cbPeripheral = ble.retrievePeripherals(withIdentifiers: [peripheralUUID])
                .first else {
                throw DeviceInfoManagerError.peripheralNotFound
            }
            
            let _ = try await ble.connect(cbPeripheral)
                .firstValue
            
            let peripheral = Peripheral(peripheral: cbPeripheral, delegate: ReactivePeripheralDelegate())
            let discoveredServices = try await peripheral.discoverServices(serviceUUIDs: nil)
                .timeout(5, scheduler: DispatchQueue.main)
                .firstValue
            
            guard let deviceInfoService = discoveredServices.first(where: {
                $0.uuid.uuidString == "180A"
            }) else {
                throw DeviceInfoManagerError.serviceNotFound
            }
            
            let discoveredCharacteristics = try await peripheral.discoverCharacteristics([], for: deviceInfoService)
                .firstValue
            
            var serial: String?
            var firmwareVersion: String?
            var hardwareVersion: String?
            var softwareType: String?
            for characteristic in discoveredCharacteristics {
                switch characteristic.uuid.uuidString {
                case "2A25": // Serial Number String
                    if let data = try await peripheral.readValue(for: characteristic).firstValue {
                        serial = String(data: data, encoding: .utf8)
                    }
                case "2A26": // Firmware Revision String
                    if let data = try await peripheral.readValue(for: characteristic).firstValue {
                        firmwareVersion = String(data: data, encoding: .utf8)
                    }
                case "2A27": // Hardware Revision String
                    if let data = try await peripheral.readValue(for: characteristic).firstValue {
                        hardwareVersion = String(data: data, encoding: .utf8)
                    }
                case "2A28": // Software Revision String
                    if let data = try await peripheral.readValue(for: characteristic).firstValue {
                        softwareType = String(data: data, encoding: .utf8)
                    }
                default:
                    continue
                }
            }
            
            if serial == nil {
                serial = try await readSerialNumberFromMDS(peripheral)
            }
            
            guard let serial, let firmwareVersion, let hardwareVersion, let softwareType else {
                throw DeviceInfoManagerError.incompleteDeviceInfo
            }
            
            return DeviceInfoToken(deviceSerialNumber: serial, hardwareVersion: hardwareVersion, currentVersion: firmwareVersion, softwareType: softwareType)
        }
    }
    
    // MARK: readSerialNumberFromMDS
    
    private func readSerialNumberFromMDS(_ peripheral: Peripheral) async throws -> String? {
        let mdsUUID = CBUUID(string: "54220000-F6A5-4007-A371-722F4EBD8436")
        let mdsServices = try await peripheral.discoverServices(serviceUUIDs: [mdsUUID])
            .timeout(5, scheduler: DispatchQueue.main)
            .firstValue
        
        // TODO: Fix bug. Should be possible to do mdsServices.first here.
        guard let mdsService = mdsServices.first(where: { $0.uuid == mdsUUID }) else {
            return nil
        }
        let discoveredCharacteristics = try await peripheral.discoverCharacteristics([], for: mdsService)
            .firstValue
        for characteristic in discoveredCharacteristics {
            switch characteristic.uuid.uuidString {
            case "54220002-F6A5-4007-A371-722F4EBD8436": // MDS Device Identifier
                if let data = try await peripheral.readValue(for: characteristic).firstValue {
                    return String(data: data, encoding: .utf8)
                }
            default:
                continue
            }
        }
        return nil // Not found
    }
}
 
// MARK: - getProjectKey

extension DeviceInfoManager {
    
    /**
     Callback-based wrapper for async ``getProjectKey()`` API.
     */
    func getProjectKey(_ callback: @escaping (Result<ProjectKey, DeviceInfoManagerError>) -> ()) {
        Task { @MainActor in
            do {
                let token = try await getProjectKey()
                callback(.success(token))
            } catch {
                guard let managerError = error as? DeviceInfoManagerError else {
                    callback(.failure(.incompleteDeviceInfo))
                    return
                }
                callback(.failure(managerError))
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    /**
     Reads ``ProjectKey`` from the Peripheral's Memfault Diagnostic (MDS) Service. Specifically from the Device Authorization Characteristic.
     
     The aforementioned ``ProjectKey`` is necessary to perform an ``OTAManager`` request for the latest Release Info for a given device.
     */
    func getProjectKey() async throws -> ProjectKey {
        do {
            try await ble.isPoweredOn()
            
            guard let cbPeripheral = ble.retrievePeripherals(withIdentifiers: [peripheralUUID])
                .first else {
                throw DeviceInfoManagerError.peripheralNotFound
            }
            
            let _ = try await ble.connect(cbPeripheral)
                .firstValue
            
            let peripheral = Peripheral(peripheral: cbPeripheral, delegate: ReactivePeripheralDelegate())
            let discoveredServices = try await peripheral.discoverServices(serviceUUIDs: nil)
                .timeout(5, scheduler: DispatchQueue.main)
                .firstValue
            
            guard let mdservice = discoveredServices.first(where: {
                $0.uuid.uuidString == "54220000-F6A5-4007-A371-722F4EBD8436"
            }) else {
                throw DeviceInfoManagerError.serviceNotFound
            }
            
            let discoveredCharacteristics = try await peripheral.discoverCharacteristics([], for: mdservice)
                .firstValue
            
            var authKey: String?
            for characteristic in discoveredCharacteristics {
                switch characteristic.uuid.uuidString {
                case "54220004-F6A5-4007-A371-722F4EBD8436": // MDS Device Authorization
                    if let data = try await peripheral.readValue(for: characteristic).firstValue {
                        authKey = String(data: data, encoding: .utf8)
                    }
                    break
                default:
                    continue
                }
            }
            
            guard let authKey else {
                throw DeviceInfoManagerError.incompleteDeviceInfo
            }
            
            guard let authToken = ProjectKey(authValue: authKey) else {
                throw DeviceInfoManagerError.mdsKeyDecodeError
            }
            return authToken
        }
    }
}
