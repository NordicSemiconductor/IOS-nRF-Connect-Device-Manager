//
//  ObservabilityChunk.swift
//  iOS-nRF-Memfault-Library
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 18/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - ObservabilityChunk

public struct ObservabilityChunk: Identifiable, Hashable, Comparable, Codable {
    
    // MARK: Status
    
    public enum Status: Equatable, Hashable, Codable {
        case pendingUpload
        case uploading
        case success
        case uploadError
    }
    
    // MARK: Properties
    
    public let sequenceNumber: UInt8
    public let data: Data
    public let timestamp: Date
    public var status: Status
    
    public var id: Int {
        hashValue
    }
    
    // MARK: Init
    
    public init(_ data: Data) {
        // Requirement to drop first byte, since it's an index / sequence number
        // and not part of the Data itself.
        self.sequenceNumber = data.first ?? .max
        self.data = data.dropFirst()
        self.timestamp = Date()
        self.status = .pendingUpload
    }
    
    // MARK: Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(sequenceNumber)
        hasher.combine(data)
        hasher.combine(status)
        hasher.combine(timestamp)
    }
    
    // MARK: Comparable
    
    public static func < (lhs: ObservabilityChunk, rhs: ObservabilityChunk) -> Bool {
        return lhs.timestamp < rhs.timestamp &&
            lhs.sequenceNumber < rhs.sequenceNumber
    }
}
