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
        super.init(group: McuMgrGroup.Statistics, transporter: transporter)
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

// MARK: - StatsManagerError

public enum StatsManagerError: UInt64, Error, LocalizedError {
    case noError = 0
    case unknown = 1
    case invalidGroup = 2
    case invalidStatName = 3
    case invalidStatSize = 4
    case abortedWalk = 5
    
    public var errorDescription: String? {
        switch self {
        case .noError:
            return "No Error Has Occurred"
        case .unknown:
            return "An Unknown Error Occurred"
        case .invalidGroup:
            return "Statistic Group Not Found"
        case .invalidStatName:
            return "Statistic Name Not Found"
        case .invalidStatSize:
            return "Size Of The Statistic Cannot Be Handled"
        case .abortedWalk:
            return "Walkthrough Of Statistics Was Aborted"
        }
    }
}
