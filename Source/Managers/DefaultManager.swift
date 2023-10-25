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
        case MemoryPoolStatistics = 3
        case DateTimeString = 4
        case Reset = 5
        case McuMgrParameters = 6
        case ApplicationInfo = 7
        case BootloaderInformation = 8
    }
    
    public enum ApplicationInfoFormat: String {
        case KernelName = "s"
        case NodeName = "n"
        case KernelRelease = "r"
        case KernelVersion = "v"
        case BuildDateTime = "b"
        case Machine = "m"
        case Processor = "p"
        case HardwarePlatform = "i"
        case OperatingSystem = "o"
        case All = "a"
    }
    
    public enum BootloaderInfoQuery: String {
        case Name = ""
        case Mode = "mode"
    }
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: McuMgrGroup.OS, transporter: transporter)
    }
    
    // MARK: - Commands

    // MARK: Echo
    
    /// Echo a string to the device.
    ///
    /// Used primarily to test Mcu Manager.
    ///
    /// - parameter echo: The string which the device will echo.
    /// - parameter callback: The response callback.
    public func echo(_ echo: String, callback: @escaping McuMgrCallback<McuMgrEchoResponse>) {
        let payload: [String:CBOR] = ["d": CBOR.utf8String(echo)]
        
        let echoPacket = McuManager.buildPacket(scheme: transporter.getScheme(), version: .SMPv2,
                                                op: .write, flags: 0, group: McuMgrGroup.OS.rawValue,
                                                sequenceNumber: 0, commandId: ID.Echo, payload: payload)
        
        guard echoPacket.count <= BasicManager.MAX_ECHO_MESSAGE_SIZE_BYTES else {
            callback(nil, EchoError.echoMessageOverTheLimit(echoPacket.count))
            return
        }
        send(op: .write, commandId: ID.Echo, payload: payload, callback: callback)
    }
    
    // MARK: (Console) Echo
    
    /// Set console echoing on the device.
    ///
    /// - parameter echoOn: Value to set console echo to.
    /// - parameter callback: The response callback.
    public func consoleEcho(_ echoOn: Bool, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = ["echo": CBOR.init(integerLiteral: echoOn ? 1 : 0)]
        send(op: .write, commandId: ID.ConsoleEchoControl, payload: payload, callback: callback)
    }
    
    // MARK: Task
    
    /// Read the task statistics for the device.
    ///
    /// - parameter callback: The response callback.
    public func taskStats(callback: @escaping McuMgrCallback<McuMgrTaskStatsResponse>) {
        send(op: .read, commandId: ID.TaskStatistics, payload: nil, callback: callback)
    }
    
    // MARK: Memory Pool
    
    /// Read the memory pool statistics for the device.
    ///
    /// - parameter callback: The response callback.
    public func memoryPoolStats(callback: @escaping McuMgrCallback<McuMgrMemoryPoolStatsResponse>) {
        send(op: .read, commandId: ID.MemoryPoolStatistics, payload: nil, callback: callback)
    }
    
    // MARK: Read/Write DateTime
    
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
    
    // MARK: Reset
    
    /// Trigger the device to soft reset.
    ///
    /// - parameter callback: The response callback.
    public func reset(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID.Reset, payload: nil, callback: callback)
    }
    
    // MARK: McuMgr Parameters
    
    /// Reads McuMgr Parameters
    ///
    /// - parameter callback: The response callback.
    public func params(callback: @escaping McuMgrCallback<McuMgrParametersResponse>) {
        send(op: .read, commandId: ID.McuMgrParameters, payload: nil, timeout: McuManager.FAST_TIMEOUT, callback: callback)
    }
    
    // MARK: Application Info
    
    /// Reads Application Info
    ///
    /// - parameter callback: The response callback.
    public func applicationInfo(format: Set<ApplicationInfoFormat>,
                                callback: @escaping McuMgrCallback<AppInfoResponse>) {
        let payload: [String:CBOR]
        if format.contains(.All) {
            payload = ["format": CBOR.utf8String(ApplicationInfoFormat.All.rawValue)]
        } else {
            payload = ["format": CBOR.utf8String(format.map({$0.rawValue}).joined(separator: ""))]
        }
        send(op: .read, commandId: ID.ApplicationInfo, payload: payload,
             timeout: McuManager.FAST_TIMEOUT, callback: callback)
    }
    
    // MARK: Bootloader Info
    
    /// Reads Bootloader Info
    ///
    /// - parameter query: The specific Bootloader Information you'd like to request.
    /// - parameter callback: The response callback.
    public func bootloaderInfo(query: BootloaderInfoQuery,
                               callback: @escaping McuMgrCallback<BootloaderInfoResponse>) {
        let payload: [String:CBOR]?
        if query == .Name {
            payload = nil
        } else {
            payload = ["query": CBOR.utf8String(query.rawValue)]
        }
        send(op: .read, commandId: ID.BootloaderInformation, payload: payload,
             timeout: McuManager.FAST_TIMEOUT, callback: callback)
    }
}

// MARK: - EchoError

enum EchoError: Hashable, Error, LocalizedError {
    
    case echoMessageOverTheLimit(_ messageSize: Int)

    var errorDescription: String? {
        switch self {
        case .echoMessageOverTheLimit(let messageSize):
            return "Echo Message of \(messageSize) bytes in size is over the limit of \(BasicManager.MAX_ECHO_MESSAGE_SIZE_BYTES) bytes."
        }
    }
}

// MARK: - OSManagerError

public enum OSManagerError: UInt64, Error, LocalizedError {
    
    case noError = 0
    case unknown = 1
    case invalidFormat = 2
    case queryNotRecognized = 3
    
    public var errorDescription: String? {
        switch self {
        case .noError:
            return "No Error Has Occurred"
        case .unknown:
            return "An Unknown Error Occurred"
        case .invalidFormat:
            return "Provided Format Value Is Not Valid"
        case .queryNotRecognized:
            return "Query Was Not Recognized (i.e. No Answer)"
        }
    }
}
