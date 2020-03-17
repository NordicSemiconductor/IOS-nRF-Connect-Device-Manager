/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public protocol McuMgrLogDelegate: class {
    
    /// Provides the delegate with content intended to be logged.
    ///
    /// - parameter msg: The text to log.
    /// - parameter level: The priority of the text being logged.
    func log(_ msg: String, atLevel level: Log.Level)
}
