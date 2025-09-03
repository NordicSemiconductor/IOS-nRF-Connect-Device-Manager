//
//  iOSOtaLibrary.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 2/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import CoreBluetooth
internal import iOS_BLE_Library_Mock

// MARK: - OTAManager

public final class OTAManager {
    
    // MARK: Private Properties
    
    private var ble = CentralManager()
    private let peripheralUUID: UUID
    private var peripheral: Peripheral?
    
    // MARK: init
    
    public init(_ targetUUID: UUID) {
        self.ble = CentralManager()
        self.peripheralUUID = targetUUID
        // Try to start inner CentralManager.
        _ = ble.centralManager.state
    }
}

// MARK: - API

public extension OTAManager {
    
    // MARK: getDeviceInfoToken
    
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

// MARK: - Private

private extension OTAManager {
    
    func awaitBleStart() async throws {
        switch ble.centralManager.state {
        case .poweredOff, .unauthorized, .unsupported:
            throw OTAManagerError.bleUnavailable
        default:
            break
        }
        
        _ = try await ble.stateChannel
            .filter {
                switch $0 {
                case .unauthorized, .unsupported, .poweredOff:
                    return false
                case .poweredOn:
                    return true
                default:
                    return false
                }
            }
            .firstValue
    }
}

// MARK: - OTAManagerError

public enum OTAManagerError: LocalizedError {
    case bleUnavailable
    case peripheralNotFound
    case serviceNotFound
    case incompleteDeviceInfo
}
