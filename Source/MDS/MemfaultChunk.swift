/*
 * Copyright (c) 2025 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Status of a Memfault chunk upload
public enum MemfaultChunkUploadStatus {
    case ready
    case uploading
    case success
    case error(Error)
}

/// Represents a chunk of Memfault diagnostic data
public class MemfaultChunk: Identifiable, Hashable {
    
    public let id = UUID()
    public let sequenceNumber: UInt16
    public let data: Data
    public let timestamp: Date
    public var uploadStatus: MemfaultChunkUploadStatus = .ready
    
    public init(sequenceNumber: UInt16, data: Data, timestamp: Date = Date()) {
        self.sequenceNumber = sequenceNumber
        self.data = data
        self.timestamp = timestamp
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: MemfaultChunk, rhs: MemfaultChunk) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - Helpers
    
    public var isReadyForUpload: Bool {
        if case .ready = uploadStatus {
            return true
        }
        return false
    }
    
    public var hasError: Bool {
        if case .error = uploadStatus {
            return true
        }
        return false
    }
}