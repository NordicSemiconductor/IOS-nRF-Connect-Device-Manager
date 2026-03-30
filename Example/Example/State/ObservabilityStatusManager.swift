//
//  ObservabilityStatusManager.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 30/3/26.
//  Copyright © 2026 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import SwiftUI
import iOSMcuManagerLibrary
import iOSOtaLibrary

// MARK: - ObservabilityStatusInfo

struct ObservabilityStatusInfo {
    
    // MARK: Properties
    
    private(set) var status: ObservabilityStatus
    private(set) var pendingCount: Int
    private(set) var pendingBytes: Int
    private(set) var uploadedCount: Int
    private(set) var uploadedBytes: Int
    
    // MARK: init
    
    init(status: ObservabilityStatus) {
        self.status = status
        self.pendingCount = 0
        self.pendingBytes = 0
        self.uploadedCount = 0
        self.uploadedBytes = 0
    }
    
    // MARK: updatedStatus()
    
    mutating func updatedStatus(_ status: ObservabilityStatus) {
        self.status = status
    }
    
    // MARK: processChunk()
    
    mutating func processChunk(_ chunk: ObservabilityChunk) {
        switch chunk.status {
        case .pendingUpload:
            pending(chunk)
        case .success:
            uploaded(chunk)
        default:
            break
        }
    }
    
    // MARK: pending()
    
    mutating func pending(_ chunk: ObservabilityChunk) {
        pendingCount += 1
        pendingBytes += chunk.data.count
    }
    
    // MARK: uploaded()
    
    mutating func uploaded(_ chunk: ObservabilityChunk) {
        pendingCount -= 1
        pendingBytes -= chunk.data.count
        
        uploadedCount += 1
        uploadedBytes += chunk.data.count
    }
    
    // MARK: pendingBytesString
    
    func pendingBytesString() -> String {
        let pendingBytesString: String
        if #available(iOS 16.0, macCatalyst 16.0, macOS 13.0, *) {
            let pendingMeasurement = Measurement<UnitInformationStorage>(value: Double(pendingBytes), unit: .bytes)
            pendingBytesString = pendingMeasurement.formatted(.byteCount(style: .file))
        } else {
            pendingBytesString = "\(pendingBytes) bytes"
        }
        return "Pending: \(pendingCount) chunk(s), \(pendingBytesString)"
    }
    
    // MARK: uploadedBytesString
    
    func uploadedBytesString() -> String {
        let uploadedBytesString: String
        if #available(iOS 16.0, macCatalyst 16.0, macOS 13.0, *) {
            let uploadedMeasurement = Measurement<UnitInformationStorage>(value: Double(uploadedBytes), unit: .bytes)
            uploadedBytesString = uploadedMeasurement.formatted(.byteCount(style: .file))
        } else {
            uploadedBytesString = "\(uploadedBytes) bytes"
        }
        return "Uploaded: \(uploadedCount) chunk(s), \(uploadedBytesString)"
    }
}
