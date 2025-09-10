//
//  MemfaultChunk.swift
//  iOS-nRF-Memfault-Library
//
//  Created by Dinesh Harjani on 18/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - MemfaultChunk

public struct ObservabilityChunk: Identifiable, Hashable {
    
    // MARK: Status
    
    public enum Status: Equatable, Hashable {
        case receivedAndPendingUpload
        case uploading
        case success
        case errorUploading
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
        self.status = .receivedAndPendingUpload
    }
    
    // MARK: Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(sequenceNumber)
        hasher.combine(data)
        hasher.combine(status)
        hasher.combine(timestamp)
    }
}
