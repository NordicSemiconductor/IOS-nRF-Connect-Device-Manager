/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Displays statistics from a device.
///
/// Stats manager can read the list of stats modules from a device and read the
/// statistics from a specific module.
public class StatsManager: McuManager {
    
    //**************************************************************************
    // MARK: Stats Constants
    //**************************************************************************

    // Mcu Stats Manager ids.
    let ID_READ = UInt8(0)
    let ID_LIST = UInt8(1)
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: .stats, transporter: transporter)
    }
    
    //**************************************************************************
    // MARK: Stats Commands
    //**************************************************************************

    /// Read statistics from a particular stats module.
    ///
    /// - parameter module: The statistics module to.
    /// - parameter callback: The response callback.
    public func read(module: String, callback: @escaping McuMgrCallback<McuMgrStatsResponse>) {
        let payload: [String:CBOR] = ["name": CBOR.utf8String(module)]
        send(op: .read, commandId: ID_READ, payload: payload, callback: callback)
    }
    
    /// List the statistic modules from a device.
    ///
    /// - parameter callback: The response callback.
    public func list(callback: @escaping McuMgrCallback<McuMgrStatsListResponse>) {
        send(op: .read, commandId: ID_LIST, payload: nil, callback: callback)
    }
}
