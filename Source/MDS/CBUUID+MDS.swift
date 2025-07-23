/*
 * Copyright (c) 2025 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import CoreBluetooth

extension CBUUID {
    
    // MARK: - Memfault Diagnostic Service (MDS)
    
    /// Memfault Diagnostic Service UUID
    static let mdsService = CBUUID(string: "54220000-F6A5-4007-A371-722F4EBD8436")
    
    /// Supported Features characteristic UUID (first characteristic)
    static let mdsSupportedFeatures = CBUUID(string: "54220001-F6A5-4007-A371-722F4EBD8436")
    
    /// Device Identifier characteristic UUID (second characteristic)
    static let mdsDeviceIdentifier = CBUUID(string: "54220002-F6A5-4007-A371-722F4EBD8436")
    
    /// Data URI characteristic UUID (third characteristic)
    static let mdsDataURI = CBUUID(string: "54220003-F6A5-4007-A371-722F4EBD8436")
    
    /// Authorization characteristic UUID (fourth characteristic - contains project key!)
    static let mdsAuthorization = CBUUID(string: "54220004-F6A5-4007-A371-722F4EBD8436")
    
    /// Data Export characteristic UUID (fifth characteristic)
    static let mdsDataExport = CBUUID(string: "54220005-F6A5-4007-A371-722F4EBD8436")
    
    // MARK: - Device Information Service (DIS)
    
    /// Standard DIS service UUID
    static let deviceInformationService = CBUUID(string: "180A")
    
    /// DIS characteristics
    static let manufacturerNameString = CBUUID(string: "2A29")
    static let modelNumberString = CBUUID(string: "2A24")
    static let serialNumberString = CBUUID(string: "2A25")
    static let hardwareRevisionString = CBUUID(string: "2A27")
    static let firmwareRevisionString = CBUUID(string: "2A26")
    static let softwareRevisionString = CBUUID(string: "2A28")
}