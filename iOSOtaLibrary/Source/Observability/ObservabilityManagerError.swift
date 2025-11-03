//
//  ObservabilityManagerError.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 8/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - ObservabilityManagerError

public enum ObservabilityManagerError: LocalizedError {
    case bleUnavailable
    case peripheralNotFound
    case pairingError
    case mdsServiceNotFound
    case mdsDataExportCharacteristicNotFound
    
    case unableToReadDeviceURI
    case unableToReadAuthData
    case missingAuthData

    public var errorDescription: String? {
        switch self {
        case .bleUnavailable:
            return "Bluetooth LE not available."
        case .peripheralNotFound:
            return "Peripheral not found."
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
