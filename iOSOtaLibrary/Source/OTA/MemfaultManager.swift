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
    
    public func readDeviceInfo() async throws -> DeviceInfoToken {
        do {
            log(msg: "Attempting to read Device Information from Memfault Group...", atLevel: .debug)
            let response: MemfaultDeviceInfoResponse? = try await asyncRead(.deviceInfo)
            if let error = response?.getError() {
                throw error
            }
            guard let token = try response?.deviceToken() else {
                throw OTAManagerError.unableToParseResponse
            }
            return token
        } catch {
            log(msg: "Error reading Device Information: \(error.localizedDescription)", atLevel: .error)
            throw error
        }
    }
    
    // MARK: readProjectKey
    
    public func readProjectKey() async throws -> ProjectKey {
        do {
            log(msg: "Attempting to read Project Key from Memfault Group...", atLevel: .debug)
            let response: MemfaultProjectKeyResponse? = try await asyncRead(.projectKey)
            if let error = response?.getError() {
                throw error
            }
            guard let projectKey = response?.projectKey() else {
                throw OTAManagerError.unableToParseResponse
            }
            return projectKey
        } catch {
            log(msg: "Error reading Project Key: \(error.localizedDescription)", atLevel: .error)
            throw error
        }
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
    
    public func deviceToken() throws(DeviceInfoTokenError) -> DeviceInfoToken? {
        guard let serial, let hardware, let software, let version else { return nil }
        return try DeviceInfoToken(deviceSerialNumber: serial, hardwareVersion: hardware,
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
