//
//  CBUUID+MDS.swift
//  iOS-nRF-Memfault-Library
//
//  Created by Dinesh Harjani on 26/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import CoreBluetooth
internal import iOS_BLE_Library_Mock

// MARK: - CBUUIDs

public extension CBUUID {
    
    static let MDS = CBUUID(string: "54220000-F6A5-4007-A371-722F4EBD8436")
    static let MDSDeviceIdentifierCharacteristic = CBUUID(string: "54220002-f6a5-4007-a371-722f4ebd8436")
    static let MDSDataURICharacteristic = CBUUID(string: "54220003-f6a5-4007-a371-722f4ebd8436")
    static let MDSAuthCharacteristic = CBUUID(string: "54220004-f6a5-4007-a371-722f4ebd8436")
    static let MDSDataExportCharacteristic = CBUUID(string: "54220005-f6a5-4007-a371-722f4ebd8436")
}
