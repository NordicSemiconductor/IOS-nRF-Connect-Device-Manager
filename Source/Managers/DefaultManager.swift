/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import SwiftCBOR

public class DefaultManager: McuManager {
    override class var TAG: McuMgrLogCategory { .default }
    
    // MARK: - Constants

    enum ID: UInt8 {
        case Echo = 0
        case ConsoleEchoControl = 1
        case TaskStatistics = 2
        case MemoryPoolStatatistics = 3
        case DateTimeString = 4
        case Reset = 5
        case McuMgrParameters = 6
    }
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: McuMgrGroup.default, transporter: transporter)
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
        
        let echoPacket = McuManager.buildPacket(scheme: transporter.getScheme(), op: .write,
                                                flags: 0, group: McuMgrGroup.default.uInt16Value,
                                                sequenceNumber: 0, commandId: ID.Echo, payload: payload)
        
        guard echoPacket.count <= BasicManager.MAX_ECHO_MESSAGE_SIZE_BYTES else {
            callback(nil, BasicManagerError.echoMessageOverTheLimit(echoPacket.count))
            return
        }
        send(op: .write, commandId: ID.Echo, payload: payload, callback: callback)
    }
    
    /// Set console echoing on the device.
    ///
    /// - parameter echoOn: Value to set console echo to.
    /// - parameter callback: The response callback.
    public func consoleEcho(_ echoOn: Bool, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = ["echo": CBOR.init(integerLiteral: echoOn ? 1 : 0)]
        send(op: .write, commandId: ID.ConsoleEchoControl, payload: payload, callback: callback)
    }
    
    /// Read the task statistics for the device.
    ///
    /// - parameter callback: The response callback.
    public func taskStats(callback: @escaping McuMgrCallback<McuMgrTaskStatsResponse>) {
        send(op: .read, commandId: ID.TaskStatistics, payload: nil, callback: callback)
    }
    
    /// Read the memory pool statistics for the device.
    ///
    /// - parameter callback: The response callback.
    public func memoryPoolStats(callback: @escaping McuMgrCallback<McuMgrMemoryPoolStatsResponse>) {
        send(op: .read, commandId: ID.MemoryPoolStatatistics, payload: nil, callback: callback)
    }
    
    /// Read the date and time on the device.
    ///
    /// - parameter callback: The response callback.
    public func readDatetime(callback: @escaping McuMgrCallback<McuMgrDateTimeResponse>) {
        send(op: .read, commandId: ID.DateTimeString, payload: nil, callback: callback)
    }
    
    /// Set the date and time on the device.
    ///
    /// - parameter date: The date and time to set the device's clock to. If
    ///   this parameter is left out, the device will be set to the current date
    ///   and time.
    /// - parameter timeZone: The time zone for the given date. If left out, the
    ///   timezone will be set to the iOS system time zone.
    /// - parameter callback: The response callback.
    public func writeDatetime(date: Date = Date(), timeZone: TimeZone? = nil,
                              callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = [
            "datetime": CBOR.utf8String(McuManager.dateToString(date: date, timeZone: timeZone))
        ]
        send(op: .write, commandId: ID.DateTimeString, payload: payload, callback: callback)
    }
    
    /// Trigger the device to soft reset.
    ///
    /// - parameter callback: The response callback.
    public func reset(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID.Reset, payload: nil, callback: callback)
    }
    
    /// Reads McuMgr Parameters
    ///
    /// - parameter callback: The response callback.
    public func params(callback: @escaping McuMgrCallback<McuMgrParametersResponse>) {
        send(op: .read, commandId: ID.McuMgrParameters, payload: nil, timeout: McuManager.FAST_TIMEOUT, callback: callback)
    }
}

