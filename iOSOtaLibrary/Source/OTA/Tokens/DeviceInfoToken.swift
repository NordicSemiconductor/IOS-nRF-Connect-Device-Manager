//
//  DeviceInfoToken.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 3/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - DeviceInfoToken

public struct DeviceInfoToken {
    
    // MARK: Properties
    
    public let deviceSerialNumber: String
    public let hardwareVersion: String
    public let currentVersion: String
    public let softwareType: String
    
    // MARK: init
    
    public init(deviceSerialNumber: String, hardwareVersion: String, currentVersion: String, softwareType: String) throws(DeviceInfoTokenError) {
        guard !deviceSerialNumber.isEmpty, !hardwareVersion.isEmpty, !currentVersion.isEmpty, !softwareType.isEmpty else {
            throw .emptyFieldFound
        }
        
        self.deviceSerialNumber = deviceSerialNumber
        self.hardwareVersion = hardwareVersion
        self.currentVersion = currentVersion
        self.softwareType = softwareType
    }
}

// MARK: - DeviceInfoTokenError

public enum DeviceInfoTokenError: LocalizedError {
    case emptyFieldFound
    
    public var errorDescription: String? {
        switch self {
        case .emptyFieldFound:
            return "DeviceInfoToken fields cannot be empty strings."
        }
    }
    
    public var failureReason: String? { errorDescription }
    
    public var recoverySuggestion: String? { errorDescription }
}
