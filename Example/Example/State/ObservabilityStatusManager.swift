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

// MARK: - ObservabilityStatusManager

final class ObservabilityStatusManager {
    
    // MARK: Properties
    
    private var observabilityTask: Task<Void, Never>?
    private var observabilityIdentifier: UUID
    private var observabilityManager: ObservabilityManager?
    
    private(set) var statusInfo: ObservabilityStatusInfo!
    private(set) var statusContinuation: AsyncStream<ObservabilityStatusInfo>.Continuation?
    
    // MARK: init
    
    init(peripheralIdentifier: UUID) {
        observabilityManager = ObservabilityManager()
        observabilityIdentifier = peripheralIdentifier
    }
    
    // MARK: deinit
    
    deinit {
        stopObservabilityManagerAndTask()
    }
    
    // MARK: start
    
    func startObservabilityTask() -> AsyncStream<ObservabilityStatusInfo> {
        if observabilityTask != nil {
            stopObservabilityManagerAndTask()
        }
        
        let stream = AsyncStream<ObservabilityStatusInfo>() { continuation in
            statusContinuation = continuation
            launchObservabilityTask()
        }
        return stream
    }
    
    // MARK: launchObservabilityTask
    
    private func launchObservabilityTask() {
        observabilityTask = Task {
            guard let observabilityStream = observabilityManager?.connectToDevice(observabilityIdentifier) else { return }
            do {
                for try await event in observabilityStream {
                    switch event.event {
                    case .connected:
                        // Reset since on Observability Connection we'll get a report of pending chunks.
                        statusInfo = ObservabilityStatusInfo(status: .receivedEvent(.connected))
                    case .updatedChunk(let chunk):
                        statusInfo?.processChunk(chunk)
                        fallthrough // updateStatus as well
                    default:
                        statusInfo?.updatedStatus(.receivedEvent(event.event))
                    }
                    guard let statusInfo else { continue } // defensive programming
                    statusContinuation?.yield(statusInfo)
                }
                print("STOPPED Listening to \(observabilityIdentifier.uuidString) Connection Events.")
                statusInfo?.updatedStatus(.connectionClosed)
                finishContinuation()
            } catch let obsError as ObservabilityError {
                print("CAUGHT ObservabilityManagerError \(obsError.localizedDescription)")
                switch obsError {
                case .mdsServiceNotFound:
                    statusInfo?.updatedStatus(.unsupported(obsError))
                case .pairingError:
                    statusInfo?.updatedStatus(.pairingError)
                default:
                    statusInfo?.updatedStatus(.errorEvent(obsError))
                }
                stopObservabilityManagerAndTask()
            } catch let error {
                print("CAUGHT Error \(error.localizedDescription) Listening to \(observabilityIdentifier.uuidString) Connection Events.")
                statusInfo?.updatedStatus(.errorEvent(error))
                stopObservabilityManagerAndTask()
            }
        }
    }
    
    // MARK: resumePendingUploads
    
    func resumePendingUploads() throws {
        try observabilityManager?.continuePendingUploads(for: observabilityIdentifier)
    }
    
    // MARK: stopObservabilityManagerAndTask
    
    func stopObservabilityManagerAndTask() {
        print(#function)
        observabilityManager?.disconnect(from: observabilityIdentifier)
        observabilityManager = nil
        observabilityTask?.cancel()
        observabilityTask = nil
        finishContinuation()
    }
    
    // MARK: finishContinuation
    
    private func finishContinuation() {
        guard let statusContinuation else { return }
        if let statusInfo {
            statusContinuation.yield(statusInfo)
        }
        statusContinuation.finish()
        self.statusContinuation = nil
    }
}

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
