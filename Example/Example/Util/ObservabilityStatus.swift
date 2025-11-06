//
//  ObservabilityStatus.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 23/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import CoreBluetooth
import iOSOtaLibrary

// MARK: - ObservabilityStatus

enum ObservabilityStatus: CustomStringConvertible {
    case unsupported(_ error: Error?)
    case receivedEvent(_ event: ObservabilityDeviceEvent)
    case connectionClosed
    case pairingError
    case errorEvent(_ error: Error)
    
    var description: String {
        switch self {
        case .unsupported:
            return "UNSUPPORTED"
        case .receivedEvent(let event):
            switch event {
            case .connected:
                return "CONNECTED"
            case .disconnected:
                return "DISCONNECTED"
            case .notifications(let enabled):
                return enabled ? "NOTIFYING" : "NOTIFICATIONS DISABLED"
            case .streaming(let isTrue):
                return isTrue ? "STREAMING" : "NOT STREAMING"
            case .authenticated:
                return "AUTHENTICATED"
            case .updatedChunk:
                return "STREAMING"
            case .unableToUpload:
                return "NETWORK UNAVAILABLE"
            }
        case .connectionClosed:
            return "DISCONNECTED"
        case .pairingError:
            return "PAIRING REQUIRED"
        case .errorEvent:
            return "ERROR"
        }
    }
}
