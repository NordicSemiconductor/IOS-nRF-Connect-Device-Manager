/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import SwiftCBOR

// MARK: - SettingsManager

public class SettingsManager: McuManager {
    override class var TAG: McuMgrLogCategory { .Settings }
    
    // MARK: IDs
    
    enum ConfigID: UInt8 {
        case Zero = 0
    }
    
    // MARK: Initializers

    public init(transporter: McuMgrTransport) {
        super.init(group: McuMgrGroup.Settings, transporter: transporter)
    }
    
    // MARK: Commands

    /// Read a system configuration variable from a device.
    ///
    /// - parameter name: The name of the system configuration variable to read.
    /// - parameter callback: The response callback.
    public func read(name: String, callback: @escaping McuMgrCallback<McuMgrConfigResponse>) {
        let payload: [String:CBOR] = ["name": CBOR.utf8String(name)]
        send(op: .read, commandId: ConfigID.Zero, payload: payload, callback: callback)
    }

    /// Write a system configuration variable on a device.
    ///
    /// - parameter name: The name of the sys config variable to write.
    /// - parameter value: The value of the sys config variable to write.
    /// - parameter callback: The response callback.
    public func write(name: String, value: String, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = ["name": CBOR.utf8String(name),
                                      "val":  CBOR.utf8String(value)]
        send(op: .write, commandId: ConfigID.Zero, payload: payload, callback: callback)
    }
}

// MARK: - SettingsManagerError

public enum SettingsManagerError: UInt64, Error, LocalizedError {
    case noError = 0
    case unknown = 1
    case keyTooLong = 2
    case keyNotFound = 3
    case readNotSupported = 4
    case rootKeyNotFound = 5
    case writeNotSupported = 6
    case deleteNotSupported = 7
    
    public var errorDescription: String? {
        switch self {
        case .noError:
            return "Success"
        case .unknown:
            return "An Unknown Error Occurred"
        case .keyTooLong:
            return "Given Key Name Is Too Long to Be Used"
        case .keyNotFound:
            return "Given Key Name Does Not Exist"
        case .readNotSupported:
            return "Desired Key Name Does Not Support Being Read"
        case .rootKeyNotFound:
            return "Desired Root Key Name Does Not Exist"
        case .writeNotSupported:
            return "Desired dKey Name Does Not Support Write Operation"
        case .deleteNotSupported:
            return "Given Key Name Does Not Support Delete Operation"
        }
    }
}
