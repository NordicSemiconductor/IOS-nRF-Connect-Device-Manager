/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import SwiftCBOR

public class ConfigManager: McuManager {
    override class var TAG: McuMgrLogCategory { .config }
    
    //**************************************************************************
    // MARK: Constants
    //**************************************************************************

    // Mcu Config Manager ids.
    let ID_CONFIG = UInt8(0)
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: McuMgrGroup.config, transporter: transporter)
    }
    
    //**************************************************************************
    // MARK: Commands
    //**************************************************************************

    /// Read a system configuration variable from a device.
    ///
    /// - parameter name: The name of the system configuration variable to read.
    /// - parameter callback: The response callback.
    public func read(name: String, callback: @escaping McuMgrCallback<McuMgrConfigResponse>) {
        let payload: [String:CBOR] = ["name": CBOR.utf8String(name)]
        send(op: .read, commandId: ID_CONFIG, payload: payload, callback: callback)
    }

    /// Write a system configuration variable on a device.
    ///
    /// - parameter name: The name of the sys config variable to write.
    /// - parameter value: The value of the sys config variable to write.
    /// - parameter callback: The response callback.
    public func write(name: String, value: String, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = ["name": CBOR.utf8String(name),
                                      "val":  CBOR.utf8String(value)]
        send(op: .write, commandId: ID_CONFIG, payload: payload, callback: callback)
    }
}
