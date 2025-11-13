//
//  ObservabilityDeviceEvent.swift
//  iOS-nRF-Memfault-Library
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 26/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - ObservabilityDeviceEvent

public enum ObservabilityDeviceEvent: CustomStringConvertible {
    
    // MARK: Case(s)
    
    case connected, disconnected
    
    case notifications(_ enabled: Bool), online(_ isTrue: Bool)
    case authenticated(_ auth: ObservabilityAuth)
    case updatedChunk(_ chunk: ObservabilityChunk)
    
    // MARK: CustomStringConvertible
    
    public var description: String {
        switch self {
        case .connected:
            return ".connected"
        case .disconnected:
            return ".disconnected"
        case .notifications(let enabled):
            return ".notifications(\(enabled ? "enabled" : "disabled"))"
        case .online(let isTrue):
            return ".online(\(isTrue ? "true" : "false"))"
        case .authenticated(_):
            return ".authenticated(_)"
        case .updatedChunk(let chunk):
            return ".updatedChunk(\(chunk.sequenceNumber), \(String(describing: chunk.status))"
        }
    }
}
