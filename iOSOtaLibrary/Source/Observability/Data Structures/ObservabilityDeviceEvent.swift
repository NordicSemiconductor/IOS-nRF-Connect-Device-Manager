//
//  MemfaultDeviceEvent.swift
//  iOS-nRF-Memfault-Library
//
//  Created by Dinesh Harjani on 26/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - MemfaultDeviceEvent

public enum ObservabilityDeviceEvent: CustomStringConvertible {
    
    // MARK: Case(s)
    
    case connected, disconnected
    
    case notifications(_ enabled: Bool), streaming(_ enabled: Bool)
    case authenticated(_ auth: ObservabilityAuth)
    case updatedChunk(_ chunk: ObservabilityChunk, status: ObservabilityChunk.Status)
    
    // MARK: CustomStringConvertible
    
    public var description: String {
        switch self {
        case .connected:
            return ".connected"
        case .disconnected:
            return ".disconnected"
        case .notifications(let enabled):
            return ".notifications(\(enabled ? "enabled" : "disabled"))"
        case .streaming(let enabled):
            return ".streaming(\(enabled ? "enabled" : "disabled"))"
        case .authenticated(_):
            return ".authenticated(_)"
        case .updatedChunk(let chunk, status: let status):
            return ".updatedChunk(\(chunk.sequenceNumber), \(String(describing: status))"
        }
    }
}
