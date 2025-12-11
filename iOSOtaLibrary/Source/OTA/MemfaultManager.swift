//
//  MemfaultManager.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 10/12/25.
//

import Foundation
import SwiftCBOR
import iOSMcuManagerLibrary

// MARK: - MemfaultManager

public class MemfaultManager: McuManager {
    
    // MARK: TAG
    
    public override class var TAG: McuMgrLogCategory { .memfault }
    
    // MARK: IDs
    
    enum CommandID: UInt8 {
        case deviceInfo = 0
        case projectKey = 1
    }
    
    // MARK: init
    
    public init(transport: McuMgrTransport) {
        super.init(group: McuMgrGroup.memfault, transport: transport)
    }
    
    // MARK: readDeviceInfo
    
    public func readDeviceInfo() async throws -> MemfaultDeviceInfoResponse? {
        try await asyncRead(.deviceInfo)
    }
    
    // MARK: readProjectKey
    
    public func readProjectKey() async throws -> MemfaultProjectKeyResponse? {
        try await asyncRead(.projectKey)
    }
    
    // MARK: Private
    
    private func asyncRead<R: McuMgrResponse>(_ command: CommandID) async throws -> R? {
        try await withCheckedThrowingContinuation { [unowned self] (continuation: CheckedContinuation<R?, Error>) in
            let callback: McuMgrCallback<R> = { response, error in
                if let error {
                    continuation.resume(throwing: error)
                }
                continuation.resume(returning: response)
            }
            send(op: .read, commandId: command, payload: nil, callback: callback)
        }
    }
}

// MARK: - MemfaultDeviceInfoResponse

public final class MemfaultDeviceInfoResponse: McuMgrResponse {
    
    public var serial: String!
    public var hardware: String!
    public var software: String!
    public var version: String!
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        
        if case let CBOR.utf8String(serial)? = cbor?["device_serial"] {
            self.serial = serial
        }
        if case let CBOR.utf8String(hardware)? = cbor?["hardware_version"] {
            self.hardware = hardware
        }
        if case let CBOR.utf8String(software)? = cbor?["software_type"] {
            self.software = software
        }
        if case let CBOR.utf8String(version)? = cbor?["current_version"] {
            self.version = version
        }
    }
    
    public func deviceToken() -> DeviceInfoToken? {
        guard let serial, let hardware, let software, let version else { return nil }
        return DeviceInfoToken(deviceSerialNumber: serial, hardwareVersion: hardware,
                               currentVersion: version, softwareType: software)
    }
}

// MARK: - MemfaultProjectKeyResponse

public final class MemfaultProjectKeyResponse: McuMgrResponse {
    
    public var key: String!
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        
        if case let CBOR.utf8String(key)? = cbor?["project_key"] {
            self.key = key
        }
    }
    
    public func projectKey() -> ProjectKey? {
        guard let key else { return nil }
        return ProjectKey(key)
    }
}
