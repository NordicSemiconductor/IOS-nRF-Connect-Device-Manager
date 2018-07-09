/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public class DefaultManager: McuManager {
    
    //**************************************************************************
    // MARK: Constants
    //**************************************************************************

    // Mcu Default Manager ids.
    let ID_ECHO           = UInt8(0)
    let ID_CONS_ECHO_CTRL = UInt8(1)
    let ID_TASKSTATS      = UInt8(2)
    let ID_MPSTAT         = UInt8(3)
    let ID_DATETIME_STR   = UInt8(4)
    let ID_RESET          = UInt8(5)
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: .default, transporter: transporter)
    }
    
    //**************************************************************************
    // MARK: Commands
    //**************************************************************************

    /// Echo a string to the device.
    ///
    /// Used primarily to test Mcu Manager.
    ///
    /// - parameter echo: The string which the device will echo.
    /// - parameter callback: The response callback.
    public func echo(_ echo: String, callback: @escaping McuMgrCallback<McuMgrEchoResponse>) {
        let payload: [String:CBOR] = ["d": CBOR.utf8String(echo)]
        send(op: .write, commandId: ID_ECHO, payload: payload, callback: callback)
    }
    
    /// Set console echoing on the device.
    ///
    /// - parameter echoOn: Value to set console echo to.
    /// - parameter callback: The response callback.
    public func consoleEcho(_ echoOn: Bool, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = ["echo": CBOR.init(integerLiteral: echoOn ? 1 : 0)]
        send(op: .write, commandId: ID_CONS_ECHO_CTRL, payload: payload, callback: callback)
    }
    
    /// Read the task statistics for the device.
    ///
    /// - parameter callback: The response callback.
    public func taskStats(callback: @escaping McuMgrCallback<McuMgrTaskStatsResponse>) {
        send(op: .read, commandId: ID_TASKSTATS, payload: nil, callback: callback)
    }
    
    /// Read the memory pool statistics for the device.
    ///
    /// - parameter callback: The response callback.
    public func memoryPoolStats(callback: @escaping McuMgrCallback<McuMgrMemoryPoolStatsResponse>) {
        send(op: .read, commandId: ID_MPSTAT, payload: nil, callback: callback)
    }
    
    /// Read the date and time on the device.
    ///
    /// - parameter callback: The response callback.
    public func readDatetime(callback: @escaping McuMgrCallback<McuMgrDateTimeResponse>) {
        send(op: .read, commandId: ID_DATETIME_STR, payload: nil, callback: callback)
    }
    
    /// Set the date and time on the device.
    ///
    /// - parameter date: The date and time to set the device's clock to. If
    ///   this parameter is left out, the device will be set to the current date
    ///   and time.
    /// - parameter timeZone: The time zone for the given date. If left out, the
    ///   timezone will be set to the iOS system time zone.
    /// - parameter callback: The response callback.
    public func writeDatetime(date: Date = Date(), timeZone: TimeZone? = nil, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = ["datetime": CBOR.utf8String(McuManager.dateToString(date: date, timeZone: timeZone))]
        send(op: .write, commandId: ID_DATETIME_STR, payload: payload, callback: callback)
    }
    
    /// Trigger the device to soft reset.
    ///
    /// - parameter callback: The response callback.
    public func reset(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID_RESET, payload: nil, callback: callback)
    }
}

