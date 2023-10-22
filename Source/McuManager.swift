/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth
import SwiftCBOR

/**
 Valid values are within the bounds of UInt8 (0...255).
 
 For capabilities such as pipelining, incrementing and wrapping around
 the Sequence Number for every `McuManager command is required.
 */
public typealias McuSequenceNumber = UInt8

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
    public static let DEFAULT_SEND_TIMEOUT_SECONDS = 40
    /// This is the default time to wait for a command to be sent, executed
    /// and received (responded to) by the firmware on the other end.
    public static let FAST_TIMEOUT = 5
    
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
    
    // MARK: Private
    
    private var smpVersion: McuMgrVersion = .SMPv2
    
    /// Each 'send' command gets its own Sequence Number, which we rotate
    /// within the bounds of an unsigned UInt8 [0...255].
    private var nextSequenceNumber: McuSequenceNumber = 0
    
    /**
     Sequence Number Response ReOrder Buffer
     */
    private var robBuffer = McuMgrROBBuffer<McuSequenceNumber, Any>()
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(group: McuMgrGroup, transporter: McuMgrTransport) {
        self.group = group
        self.transporter = transporter
        self.mtu = McuManager.getDefaultMtu(scheme: transporter.getScheme())
    }
    
    // MARK: - Send
    
    public func send<T: McuMgrResponse, R: RawRepresentable>(op: McuMgrOperation, commandId: R, payload: [String:CBOR]?,
                                                             timeout: Int = DEFAULT_SEND_TIMEOUT_SECONDS,
                                                             callback: @escaping McuMgrCallback<T>) where R.RawValue == UInt8 {
        return send(op: op, flags: 0, commandId: commandId, payload: payload, timeout: timeout,
                    callback: callback)
    }
    
    public func send<T: McuMgrResponse, R: RawRepresentable>(op: McuMgrOperation, flags: UInt8,
                                                             commandId: R, payload: [String:CBOR]?,
                                                             timeout: Int = DEFAULT_SEND_TIMEOUT_SECONDS,
                                                             callback: @escaping McuMgrCallback<T>) where R.RawValue == UInt8 {
        log(msg: "Sending \(op) command (Version: \(smpVersion), Group: \(group), seq: \(nextSequenceNumber), ID: \(commandId)): \(payload?.debugDescription ?? "nil")",
            atLevel: .verbose)
        let packetSequenceNumber = nextSequenceNumber
        let packetData = McuManager.buildPacket(scheme: transporter.getScheme(), version: smpVersion,
                                                op: op, flags: flags, group: group.rawValue,
                                                sequenceNumber: packetSequenceNumber,
                                                commandId: commandId, payload: payload)
        let _callback: McuMgrCallback<T> = { [weak self] (response, error) -> Void in
            guard let self else {
                callback(response, error)
                return
            }
            
            do {
                guard try self.robBuffer.receivedInOrder((response, error), for: packetSequenceNumber) else { return }
                try self.robBuffer.deliver { responseSequenceNumber, response in
                    let responseResult = response as? (T?, (any Error)?)
                    if let response = responseResult?.0 {
                        self.smpVersion = McuMgrVersion(rawValue: response.header.version) ?? .SMPv1
                        self.log(msg: "Response (Version: \(self.smpVersion), Group: \(self.group), seq: \(responseSequenceNumber), ID: \(response.header!.commandId!)): \(response)",
                                 atLevel: .verbose)
                    } else if let error = responseResult?.1 {
                        self.log(msg: "Request (Version: \(self.smpVersion), Group: \(self.group), seq: \(responseSequenceNumber)) failed: \(error.localizedDescription))",
                                 atLevel: .error)
                    }
                    callback(responseResult?.0, responseResult?.1)
                }
            } catch let robBufferError {
                DispatchQueue.main.async {
                    callback(response, robBufferError)
                }
            }
        }
        
        robBuffer.expectingValue(for: packetSequenceNumber)
        send(data: packetData, timeout: timeout, callback: _callback)
        rotateSequenceNumber()
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
    /// - parameter version: The SMP Version.
    /// - parameter op: The McuManagerOperation code.
    /// - parameter flags: The optional flags.
    /// - parameter group: The command group.
    /// - parameter sequenceNumber: The optional sequence number.
    /// - parameter commandId: The command id.
    /// - parameter payload: The request payload.
    ///
    /// - returns: The raw packet data to send to the transporter.
    public static func buildPacket<R: RawRepresentable>(scheme: McuMgrScheme,
                                                        version: McuMgrVersion,
                                                        op: McuMgrOperation,
                                                        flags: UInt8, group: UInt16,
                                                        sequenceNumber: McuSequenceNumber,
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
        let header = McuMgrHeader.build(version: version.rawValue, op: op.rawValue, flags: flags,
                                        len: len, group: group, seq: sequenceNumber,
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
    
    static let ValidMTURange = 73...1024
    
    public func setMtu(_ mtu: Int) throws  {
        guard Self.ValidMTURange.contains(mtu) else {
            throw McuManagerError.mtuValueOutsideOfValidRange(mtu)
        }
        guard self.mtu != mtu else {
            throw McuManagerError.mtuValueHasNotchanged(mtu)
        }
        
        self.mtu = mtu
        log(msg: "MTU set to \(mtu)", atLevel: .info)
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
    
    private func rotateSequenceNumber() {
        nextSequenceNumber = nextSequenceNumber == .max ? 0 : nextSequenceNumber + 1
    }
}

// MARK: - McuManagerCallback

public typealias McuMgrCallback<T: McuMgrResponse> = (T?, Error?) -> Void

// MARK: - McuManagerError

public enum McuManagerError: Error, LocalizedError {
    
    case mtuValueOutsideOfValidRange(_ newValue: Int)
    case mtuValueHasNotchanged(_ newValue: Int)
    case returnCode(_ rc: McuMgrReturnCode)
    case returnCodeValue(_ rc: UInt64)
    
    public var errorDescription: String? {
        switch self {
        case .mtuValueOutsideOfValidRange(let newMtu):
            return "New MTU Value \(newMtu) is outside valid range of \(McuManager.ValidMTURange.lowerBound)...\(McuManager.ValidMTURange.upperBound)"
        case .mtuValueHasNotchanged(let newMtu):
            return "MTU Value already set to \(newMtu)"
        case .returnCode(let rc):
            return "Remote Error: \(rc)"
        case .returnCodeValue(let code):
            return "Remote Error: \(code)"
        }
    }
}

// MARK: - McuMgrGroup

/// The defined groups for Mcu Manager commands.
///
/// Each group has its own manager class which contains the specific subcommands
/// and functions. The default are contained within the McuManager class.
public enum McuMgrGroup: UInt16 {
    /// Default command group (DefaultManager).
    case OS = 0
    /// Image command group (ImageManager).
    case Image = 1
    /// Statistics command group (StatsManager).
    case Statistics = 2
    /// System configuration command group (ConfigManager).
    case Settings = 3
    /// Log command group (LogManager).
    case Logs = 4
    /// Crash command group (CrashManager).
    case Crash = 5
    /// Split image command group (Not implemented).
    case Split = 6
    /// Run test command group (RunManager).
    case Run = 7
    /// File System command group (FileSystemManager).
    case Filesystem = 8
    /// Shell Command Group (Not Implemented).
    case Shell = 9
    /// Per user command group, value must be >= 64.
    case PerUser = 64
    
    /** 
     * Basic command group (BasicManager).
     *
     * Zephyr-specific groups decrease from PERUSER to avoid collision with upstream and
     * user-defined groups.
     */
    case Basic = 63 // PerUser - 1
}

// MARK: - McuMgrVersion

/// The mcu manager operation defines whether the packet sent is a read/write
/// and request/response.
public enum McuMgrVersion: UInt8, CustomStringConvertible {
    case SMPv1 = 0
    case SMPv2 = 1
    
    public var description: String {
        switch self {
        case .SMPv1:
            return "SMPv1"
        case .SMPv2:
            return "SMPv2"
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

public enum McuMgrError: Error, LocalizedError {
    case returnCode(_ rc: McuMgrReturnCode)
    case groupCode(_ group: McuMgrGroupReturnCode)
    
    public var errorDescription: String? {
        switch self {
        case .returnCode(let rc):
            return rc.description
        case .groupCode(let groupCode):
            return groupCode.groupError()?.errorDescription
        }
    }
}

public class McuMgrGroupReturnCode: CBORMappable {
    
    public var group: UInt64 = 0
    
    public var rc: UInt64 = 0
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        if case let CBOR.unsignedInt(group)? = cbor?["group"] {
            self.group = group
        }
        if case let CBOR.unsignedInt(rc)? = cbor?["rc"] {
            self.rc = rc
        }
    }
    
    public init(map: [CBOR: CBOR]) throws {
        try super.init(cbor: nil)
        if case let CBOR.unsignedInt(group)? = map["group"] {
            self.group = group
        }
        if case let CBOR.unsignedInt(rc)? = map["rc"] {
            self.rc = rc
        }
    }
    
    public func groupError() -> LocalizedError? {
        guard rc != 0 else { return nil }
        
        let error: LocalizedError?
        switch McuMgrGroup(rawValue: UInt16(group)) {
        case .OS:
            error = OSManagerError(rawValue: rc)
        case .Image:
            error = ImageManagerError(rawValue: rc)
        case .Statistics:
            error = StatsManagerError(rawValue: rc)
        case .Filesystem:
            error = FileSystemManagerError(rawValue: rc)
        case .Basic:
            error = BasicManagerError(rawValue: rc)
        default:
            // Passthrough to McuMgr 'RC' Errors for Unkwnon
            // or Unsupported values.
            error = McuManagerError.returnCodeValue(rc)
        }
        return error ?? McuManagerError.returnCodeValue(rc)
    }
}

// MARK: - McuMgrReturnCode

/// Return codes for Mcu Manager responses.
///
/// Each Mcu Manager response will contain a "rc" key with one of these return
/// codes.
public enum McuMgrReturnCode: UInt64, Error {
    case ok                = 0
    case unknown           = 1
    case noMemory          = 2
    case inValue           = 3
    case timeout           = 4
    case noEntry           = 5
    case badState          = 6
    case responseIsTooLong = 7
    case unsupported       = 8
    case corruptPayload    = 9
    case busy              = 10
    case accessDenied      = 11
    
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
            return "OK (RC: \(rawValue))"
        case .unknown:
            return "Unknown (RC: \(rawValue))"
        case .noMemory:
            return "No Memory (RC: \(rawValue))"
        case .inValue:
            return "In Value (RC: \(rawValue))"
        case .timeout:
            return "Timeout (RC: \(rawValue))"
        case .noEntry:
            return "No Entry (RC: \(rawValue)). For Filesystem Operations, Does Your Mounting Point Match Your Target Firmware / Device?"
        case .badState:
            return "Bad State (RC: \(rawValue))"
        case .responseIsTooLong:
            return "Response is Too Long (RC: \(rawValue))"
        case .unsupported:
            return "Not Supported (RC: \(rawValue)). Requested Group ID or Command ID May Not Supported by This Application."
        case .corruptPayload:
            return "Corrupt Payload (RC: \(rawValue))"
        case .busy:
            return "Busy Processing Previous SMP Request (RC: \(rawValue)). Wait and Try Later."
        case .accessDenied:
            return "Access Denied (RC: \(rawValue)). Are You Trying to Downgrade to a Lower Image Version?"
        default:
            return "Unrecognized (RC: \(rawValue))"
        }
    }
}
