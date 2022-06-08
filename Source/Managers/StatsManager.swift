/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import SwiftCBOR

/// Displays statistics from a device.
///
/// Stats manager can read the list of stats modules from a device and read the
/// statistics from a specific module.
public class StatsManager: McuManager {
    override class var TAG: McuMgrLogCategory { .stats }
    
    // MARK: - IDs
    
    enum StatsID: UInt8 {
        case Read = 0
        case List = 1
    }
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: McuMgrGroup.stats, transporter: transporter)
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
        send(op: .read, commandId: StatsID.Read, payload: payload, callback: callback)
    }
    
    /// List the statistic modules from a device.
    ///
    /// - parameter callback: The response callback.
    public func list(callback: @escaping McuMgrCallback<McuMgrStatsListResponse>) {
        send(op: .read, commandId: StatsID.List, payload: nil, callback: callback)
    }
}
