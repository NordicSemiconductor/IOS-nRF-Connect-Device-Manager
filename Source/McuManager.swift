/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth
import SwiftCBOR

open class McuManager {
    class var TAG: McuMgrLogCategory { .default }
    
    //**************************************************************************
    // MARK: Mcu Manager Constants
    //**************************************************************************
    
    /// Mcu Manager CoAP Resource URI.
    public static let COAP_PATH = "/omgr"
    
    /// Header Key for CoAP Payloads.
    public static let HEADER_KEY = "_h"
    
    /// If a specific Timeout is not set, the number of seconds that will be
    /// allowed to elapse before a send request is considered to have failed
    /// due to a timeout if no response is received.
    public static let DEFAULT_SEND_TIMEOUT_SECONDS = 30
    
    //**************************************************************************
    // MARK: Properties
    //**************************************************************************

    /// Handles transporting Mcu Manager commands.
    public let transporter: McuMgrTransport
    
    /// The command group used for in the header of commands sent using this Mcu
    /// Manager.
    public let group: McuMgrGroup
    
    /// The MTU used by this manager. This value must be between 23 and 1024.
    /// The MTU is usually only a factor when uploading files or images to the
    /// device, where each request should attempt to maximize the amount of
    /// data being sent to the device.
    public var mtu: Int
    
    /// Logger delegate will receive logs.
    public weak var logDelegate: McuMgrLogDelegate?
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(group: McuMgrGroup, transporter: McuMgrTransport) {
        self.group = group
        self.transporter = transporter
        self.mtu = McuManager.getDefaultMtu(scheme: transporter.getScheme())
    }
    
    // MARK: - Send
    
    public func send<T: McuMgrResponse, R: RawRepresentable>(op: McuMgrOperation, sequenceNumber: UInt8 = 0,
                                                             commandId: R, payload: [String:CBOR]?,
                                                             timeout: Int = DEFAULT_SEND_TIMEOUT_SECONDS,
                                                             callback: @escaping McuMgrCallback<T>) where R.RawValue == UInt8 {
        send(op: op, sequenceNumber: sequenceNumber, flags: 0, commandId: commandId, payload: payload, timeout: timeout,
             callback: callback)
    }
    
    public func send<T: McuMgrResponse, R: RawRepresentable>(op: McuMgrOperation, sequenceNumber: UInt8,
                                                             flags: UInt8, commandId: R, payload: [String:CBOR]?,
                                                             timeout: Int = DEFAULT_SEND_TIMEOUT_SECONDS,
                                                             callback: @escaping McuMgrCallback<T>) where R.RawValue == UInt8 {
        log(msg: "Sending \(op) command (Group: \(group), seq: \(sequenceNumber), ID: \(commandId)): \(payload?.debugDescription ?? "nil")",
            atLevel: .verbose)
        let mcuPacketData = McuManager.buildPacket(scheme: transporter.getScheme(), op: op,
                                                   flags: flags, group: group.uInt16Value,
                                                   sequenceNumber: sequenceNumber,
                                                   commandId: commandId, payload: payload)
        let _callback: McuMgrCallback<T> = logDelegate == nil ? callback : { [weak self] (response, error) in
            if let self = self {
                if let response = response {
                    self.log(msg: "Response (Group: \(self.group), seq: \(sequenceNumber), ID: \(response.header!.commandId!)): \(response)",
                             atLevel: .verbose)
                } else if let error = error {
                    self.log(msg: "Request (Group: \(self.group), seq: \(sequenceNumber)) failed: \(error.localizedDescription))",
                             atLevel: .error)
                }
            }
            callback(response, error)
        }
        send(data: mcuPacketData, timeout: timeout, callback: _callback)
    }
    
    public func send<T: McuMgrResponse>(data: Data, timeout: Int, callback: @escaping McuMgrCallback<T>) {
        transporter.send(data: data, timeout: timeout, callback: callback)
    }
    
    //**************************************************************************
    // MARK: Build Request Packet
    //**************************************************************************
    
    /// Build a McuManager request packet based on the transporter scheme.
    ///
    /// - parameter scheme: The transport scheme.
    /// - parameter op: The McuManagerOperation code.
    /// - parameter flags: The optional flags.
    /// - parameter group: The command group.
    /// - parameter sequenceNumber: The optional sequence number.
    /// - parameter commandId: The command id.
    /// - parameter payload: The request payload.
    ///
    /// - returns: The raw packet data to send to the transporter.
    public static func buildPacket<R: RawRepresentable>(scheme: McuMgrScheme, op: McuMgrOperation, flags: UInt8,
                                                        group: UInt16, sequenceNumber: UInt8,
                                                        commandId: R, payload: [String:CBOR]?) -> Data where R.RawValue == UInt8 {
        // If the payload map is nil, initialize an empty map.
        var payload = (payload == nil ? [:] : payload)!
        
        // Copy the payload map to remove the header key.
        var payloadCopy = payload
        // Remove the header if present (for CoAP schemes).
        payloadCopy.removeValue(forKey: McuManager.HEADER_KEY)
        
        // Get the length.
        let len: UInt16 = UInt16(CBOR.encode(payloadCopy).count)
        
        // Build header.
        let header = McuMgrHeader.build(op: op.rawValue, flags: flags, len: len,
                                        group: group, seq: sequenceNumber,
                                        id: commandId.rawValue)
        
        // Build the packet based on scheme.
        if scheme.isCoap() {
            // CoAP transport schemes puts the header as a key-value pair in the
            // payload.
            if payload[McuManager.HEADER_KEY] == nil {
                payload.updateValue(CBOR.byteString(header), forKey: McuManager.HEADER_KEY)
            }
            return Data(CBOR.encode(payload))
        } else {
            // Standard scheme appends the CBOR payload to the header.
            let cborPayload = CBOR.encode(payload)
            var packet = Data(header)
            packet.append(contentsOf: cborPayload)
            return packet
        }
    }
    
    //**************************************************************************
    // MARK: Utilities
    //**************************************************************************

    /// Converts a date and optional timezone to a string which Mcu Manager on
    /// the device can use.
    ///
    /// The date format used is: "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
    ///
    /// - parameter date: The date.
    /// - parameter timeZone: Optional timezone for the given date. If left out
    ///   or nil, the timzone will be set to the system time zone.
    ///
    /// - returns: The datetime string.
    public static func dateToString(date: Date, timeZone: TimeZone? = nil) -> String {
        let RFC3339DateFormatter = DateFormatter()
        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        RFC3339DateFormatter.timeZone = (timeZone != nil ? timeZone : TimeZone.current)
        return RFC3339DateFormatter.string(from: date)
    }
    
    /// Set the MTU used by this McuManager. The McuManager MTU must be between
    /// 23 and 1024 (inclusive). The MTU generally only matters when uploading
    /// to the device, where the upload data in each request should be
    /// maximized.
    ///
    /// - parameter mtu: The mtu to set.
    ///
    /// - returns: true if the value is between 23 and 1024 (inclusive), false
    ///   otherwise
    public func setMtu(_ mtu: Int) -> Bool {
        if mtu >= 23 && mtu <= 1024 {
            self.mtu = mtu
            log(msg: "MTU set to \(mtu)", atLevel: .info)
            return true
        } else {
            log(msg: "Invalid MTU (\(mtu)): Value must be between 23 and 1024", atLevel: .warning)
            return false
        }
    }
    
    /// Get the default MTU which should be used for a transport scheme. If the
    /// scheme is BLE, the iOS version is used to determine the MTU. If the
    /// scheme is UDP, the MTU returned is always 1024.
    ///
    /// - parameter scheme: the transporter
    public static func getDefaultMtu(scheme: McuMgrScheme) -> Int {
        // BLE MTU is determined by the version of iOS running on the device
        if scheme.isBle() {
            /// Return the maximum BLE ATT MTU for this iOS device.
            if #available(iOS 11.0, *) {
                // For iOS 11.0+ (527 - 3)
                return 524
            } else if #available(iOS 10.0, *) {
                // For iOS 10.0 (185 - 3)
                return 182
            } else {
                // For iOS 9.0 (158 - 3)
                return 155
            }
        } else {
            return 1024
        }
    }
}

extension McuManager {
    
    func log(msg: @autoclosure () -> String, atLevel level: McuMgrLogLevel) {
        logDelegate?.log(msg(), ofCategory: Self.TAG, atLevel: level)
    }
    
}

/// McuManager callback
public typealias McuMgrCallback<T: McuMgrResponse> = (T?, Error?) -> Void

// MARK: - McuMgrGroup

/// The defined groups for Mcu Manager commands.
///
/// Each group has its own manager class which contains the specific subcommands
/// and functions. The default are contained within the McuManager class.
public enum McuMgrGroup {
    /// Default command group (DefaultManager).
    case `default`
    /// Image command group (ImageManager).
    case image
    /// Statistics command group (StatsManager).
    case stats
    /// System configuration command group (ConfigManager).
    case config
    /// Log command group (LogManager).
    case logs
    /// Crash command group (CrashManager).
    case crash
    /// Split image command group (Not implemented).
    case split
    /// Run test command group (RunManager).
    case run
    /// File System command group (FileSystemManager).
    case fs
    /// Basic command group (BasicManager).
    case basic
    /// Per user command group, value must be >= 64.
    case peruser(value: UInt16)
    
    var uInt16Value: UInt16 {
        switch self {
        case .default: return 0
        case .image: return 1
        case .stats: return 2
        case .config: return 3
        case .logs: return 4
        case .crash: return 5
        case .split: return 6
        case .run: return 7
        case .fs: return 8
        case .basic: return 63
        case .peruser(let value): return value
        }
    }
}

// MARK: - McuMgrOperation

/// The mcu manager operation defines whether the packet sent is a read/write
/// and request/response.
public enum McuMgrOperation: UInt8 {
    case read           = 0
    case readResponse   = 1
    case write          = 2
    case writeResponse  = 3
}

// MARK: - McuMgrReturnCode

/// Return codes for Mcu Manager responses.
///
/// Each Mcu Manager response will contain a "rc" key with one of these return
/// codes.
public enum McuMgrReturnCode: UInt64, Error {
    case ok         = 0
    case unknown    = 1
    case noMemory   = 2
    case inValue    = 3
    case timeout    = 4
    case noEntry    = 5
    case badState   = 6
    case unrecognized
    
    public func isSuccess() -> Bool {
        return self == .ok
    }
    
    public func isError() -> Bool {
        return self != .ok
    }
}

extension McuMgrReturnCode: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .ok:
            return "OK (0)"
        case .unknown:
            return "Unknown (1)"
        case .noMemory:
            return "No Memory (2)"
        case .inValue:
            return "In Value (3)"
        case .timeout:
            return "Timeout (4)"
        case .noEntry:
            return "No Entry (5)"
        case .badState:
            return "Bad State (1)"
        default:
            return "Unrecognized (\(rawValue))"
        }
    }
}
