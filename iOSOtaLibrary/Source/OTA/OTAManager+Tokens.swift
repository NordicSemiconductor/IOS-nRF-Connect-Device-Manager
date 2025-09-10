//
//  OTAManager+Tokens.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 3/9/25.
//

import Foundation
import CoreBluetooth
internal import iOS_BLE_Library_Mock

// MARK: - getDeviceInfoToken

public extension OTAManager {
    
    func getDeviceInfoToken(_ callback: @escaping (Result<DeviceInfoToken, OTAManagerError>) -> ()) {
        Task { @MainActor in
            do {
                let token = try await getDeviceInfoToken()
                callback(.success(token))
            } catch {
                guard let otaError = error as? OTAManagerError else {
                    callback(.failure(.incompleteDeviceInfo))
                    return
                }
                callback(.failure(otaError))
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    func getDeviceInfoToken() async throws -> DeviceInfoToken {
        do {
            try await awaitBleStart()
            
            let cbPeripheral = ble.retrievePeripherals(withIdentifiers: [peripheralUUID])
                .first
            
            guard let cbPeripheral else {
                throw OTAManagerError.peripheralNotFound
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
                throw OTAManagerError.serviceNotFound
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
            
            guard let serial, let firmwareVersion, let hardwareVersion, let softwareType else {
                throw OTAManagerError.incompleteDeviceInfo
            }
            
            return DeviceInfoToken(deviceSerialNumber: serial, hardwareVersion: hardwareVersion, currentVersion: firmwareVersion, softwareType: softwareType)
        }
    }
}
 
// MARK: - getProjectKey

public extension OTAManager {
    
    func getProjectKey(_ callback: @escaping (Result<ProjectKey, OTAManagerError>) -> ()) {
        Task { @MainActor in
            do {
                let token = try await getProjectKey()
                callback(.success(token))
            } catch {
                guard let otaError = error as? OTAManagerError else {
                    callback(.failure(.incompleteDeviceInfo))
                    return
                }
                callback(.failure(otaError))
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    func getProjectKey() async throws -> ProjectKey {
        do {
            try await awaitBleStart()
            
            let cbPeripheral = ble.retrievePeripherals(withIdentifiers: [peripheralUUID])
                .first
            
            guard let cbPeripheral else {
                throw OTAManagerError.peripheralNotFound
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
                throw OTAManagerError.serviceNotFound
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
                throw OTAManagerError.incompleteDeviceInfo
            }
            
            guard let authToken = ProjectKey(authValue: authKey) else {
                throw OTAManagerError.mdsKeyDecodeError
            }
            return authToken
        }
    }
}
