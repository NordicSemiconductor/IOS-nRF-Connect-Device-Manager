//
//  DefaultManager+Task.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 26/3/26.
//  Copyright © 2026 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import iOSMcuManagerLibrary

// MARK: - DefaultManager+Task

public extension DefaultManager {
    
    // MARK: async params()
    
    public func params() async throws -> (bufferCount: Int, bufferSize: Int) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(bufferCount: Int, bufferSize: Int), Error>) in
            params { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let count = response?.bufferCount,
                   let size = response?.bufferSize {
                    continuation.resume(returning: (Int(count), Int(size)))
                } else {
                    continuation.resume(throwing: McuMgrResponseParseError.invalidPayload)
                }
            }
        }
    }
    
    // MARK: async applicationInfo(format:)
    
    public func applicationInfo(format: Set<ApplicationInfoFormat>) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            applicationInfo(format: format) { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let response = response?.response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: McuMgrResponseParseError.invalidPayload)
                }
            }
        }
    }
    
    // MARK: bootloaderInfo()
    
    public func bootloaderInfo() async throws -> (bootloader: BootloaderInfoResponse.Bootloader?, mode: BootloaderInfoResponse.Mode?, slot: UInt64?) {
        let bootloader = try await bootloaderQuery(.name).bootloader
        guard bootloader == .mcuboot else { return (bootloader: bootloader, mode: nil, slot: nil) }
        
        let mode = try await bootloaderQuery(.mode).mode
        let slot = try await bootloaderQuery(.slot).activeSlot
        return (bootloader: bootloader, mode: mode, slot: slot)
    }
    
    // MARK: bootloaderQuery(:)
    
    public func bootloaderQuery(_ query: BootloaderInfoQuery) async throws -> BootloaderInfoResponse {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BootloaderInfoResponse, Error>) in
            bootloaderInfo(query: query) { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: McuMgrResponseParseError.invalidPayload)
                }
            }
        }
    }
}
