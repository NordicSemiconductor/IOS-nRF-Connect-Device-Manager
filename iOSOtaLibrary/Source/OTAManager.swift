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
    
    internal var ble = CentralManager()
    internal let peripheralUUID: UUID
    internal var peripheral: Peripheral?
    
    // MARK: init
    
    public init(_ targetPeripheralUUID: UUID) {
        self.ble = CentralManager()
        self.peripheralUUID = targetPeripheralUUID
        // Try to start inner CentralManager.
        _ = ble.centralManager.state
    }
}

// MARK: - API

public extension OTAManager {
    
    func getLatestFirmware(deviceInfo: DeviceInfoToken, projectKey: ProjectKey) {
        
    }
}

// MARK: - Private

extension OTAManager {
    
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
    case mdsKeyDecodeError
}
