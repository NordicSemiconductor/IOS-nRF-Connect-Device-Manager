//
//  ObservabilityError.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 8/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - ObservabilityError

public enum ObservabilityError: LocalizedError {
    
    // BLE Connection
    case bleUnavailable
    case peripheralNotFound
    case peripheralNotConnected
    case pairingError
    case mdsServiceNotFound
    case mdsDataExportCharacteristicNotFound
    
    // Authentication
    case unableToReadDeviceURI
    case unableToReadAuthData
    case missingAuthData

    public var errorDescription: String? {
        switch self {
        case .bleUnavailable:
            return "Bluetooth LE not available."
        case .peripheralNotFound:
            return "Peripheral not found."
        case .peripheralNotConnected:
            return "Peripheral not connected."
        case .pairingError:
            return "Pairing Error."
        case .mdsServiceNotFound:
            return "Memfault Diagnostic Service (MDS) not found."
        case .mdsDataExportCharacteristicNotFound:
            return "MDS Data Export Characteristic not found."
        case .unableToReadDeviceURI:
            return "Unable to parse Device URI."
        case .unableToReadAuthData:
            return "Unable to read Authentication Data."
        case .missingAuthData:
            return "Missing Authentication Data."
        }
    }
}
