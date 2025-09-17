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
    
    public init(deviceSerialNumber: String, hardwareVersion: String, currentVersion: String, softwareType: String) {
        self.deviceSerialNumber = deviceSerialNumber
        self.hardwareVersion = hardwareVersion
        self.currentVersion = currentVersion
        self.softwareType = softwareType
    }
}
