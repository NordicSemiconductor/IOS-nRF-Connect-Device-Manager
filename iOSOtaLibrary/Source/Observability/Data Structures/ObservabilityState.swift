//
//  ObservabilityState.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 4/11/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - ObservabilityState

nonisolated
struct ObservabilityState: Codable {
    
    // MARK: Properties
    
    internal var pendingUploads = [UUID: [ObservabilityChunk]]()
    
    // MARK: API
    
    mutating func add(_ chunks: [ObservabilityChunk], for identifier: UUID) {
        if pendingUploads[identifier] == nil {
            pendingUploads[identifier] = [ObservabilityChunk]()
        }
        
        pendingUploads[identifier]?.append(contentsOf: chunks)
        pendingUploads[identifier]?.sorted {
            return $0.sequenceNumber < $1.sequenceNumber && $0.timestamp < $1.timestamp
        }
    }
    
    func nextChunk(for identifier: UUID) -> ObservabilityChunk? {
        return pendingUploads[identifier]?.first
    }
    
    mutating func finishedUploading(_ chunk: ObservabilityChunk, from identifier: UUID) {
        guard let index = pendingUploads[identifier]?.firstIndex(of: chunk) else {
            return
        }
        pendingUploads[identifier]?.remove(at: index)
    }
}

// MARK: Save / Restore

extension ObservabilityState {
    
    func restoreFromDisk() {
        // TODO
    }
    
    func saveToDisk() {
        // TODO
    }
}
