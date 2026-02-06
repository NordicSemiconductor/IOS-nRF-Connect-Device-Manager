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
    
    public init(deviceSerialNumber: String?, hardwareVersion: String?, currentVersion: String?, softwareType: String?) throws(DeviceInfoTokenError) {
        guard let deviceSerialNumber else {
            throw .initNilParameterFound("deviceSerialNumber")
        }
        guard let hardwareVersion else {
            throw .initNilParameterFound("hardwareVersion")
        }
        guard let currentVersion else {
            throw .initNilParameterFound("currentVersion")
        }
        guard let softwareType else {
            throw .initNilParameterFound("softwareType")
        }
        
        guard !deviceSerialNumber.isEmpty else {
            throw .initEmptyParameterFound("deviceSerialNumber")
        }
        guard !hardwareVersion.isEmpty else {
            throw .initEmptyParameterFound("hardwareVersion")
        }
        guard !currentVersion.isEmpty else {
            throw .initEmptyParameterFound("currentVersion")
        }
        guard !softwareType.isEmpty else {
            throw .initEmptyParameterFound("softwareType")
        }
        
        self.deviceSerialNumber = deviceSerialNumber
        self.hardwareVersion = hardwareVersion
        self.currentVersion = currentVersion
        self.softwareType = softwareType
    }
}

// MARK: - DeviceInfoTokenError

public enum DeviceInfoTokenError: LocalizedError {
    case initNilParameterFound(_ named: String)
    case initEmptyParameterFound(_ named: String)
    
    public var errorDescription: String? {
        switch self {
        case .initNilParameterFound(let parameterName):
            return "DeviceInfoToken's init() was passed a nil \(parameterName) parameter."
        case .initEmptyParameterFound(let parameterName):
            return "DeviceInfoToken's init() was passed an empty \(parameterName) String."
        }
    }
    
    public var failureReason: String? { errorDescription }
    
    public var recoverySuggestion: String? { errorDescription }
}
