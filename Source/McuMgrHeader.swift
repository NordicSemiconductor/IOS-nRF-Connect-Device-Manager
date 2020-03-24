/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Represents an 8-byte McuManager header.
public class McuMgrHeader {
    
    /// Header length.
    public static let HEADER_LENGTH = 8
    
    public let op: UInt8!
    public let flags: UInt8!
    public let length: UInt16!
    public let groupId: UInt16!
    public let sequenceNumber: UInt8!
    public let commandId: UInt8!
    
    /// Initialize the header with raw data. Because this method only parses the
    /// first eight bytes of the input data, the data's count must be greater or
    /// equal than eight.
    ///
    /// - parameter data: The data to parse. Data count must be greater than or
    ///   equal to eight.
    /// - throws: McuMgrHeaderParseException.invalidSize(Int) if the data count
    ///   is too small.
    public init(data: Data) throws {
        if (data.count < McuMgrHeader.HEADER_LENGTH) {
            throw McuMgrHeaderParseError.invalidSize(data.count)
        }
        op = data[0]
        flags = data[1]
        length = data.readBigEndian(offset: 2)
        groupId = data.readBigEndian(offset: 4)
        sequenceNumber = data[6]
        commandId = data[7]
    }
    
    public init(op: UInt8, flags: UInt8, length: UInt16, groupId: UInt16, sequenceNumber: UInt8, commandId: UInt8) {
        self.op = op
        self.flags = flags
        self.length = length
        self.groupId = groupId
        self.sequenceNumber = sequenceNumber
        self.commandId = commandId
    }
    
    public func toData() -> Data {
        var data = Data(count: McuMgrHeader.HEADER_LENGTH)
        data.append(op)
        data.append(flags)
        data.append(Data(from: length))
        data.append(Data(from: groupId))
        data.append(sequenceNumber)
        data.append(commandId)
        return data
    }
    
    /// Helper function to build a raw mcu manager header.
    ///
    /// - parameter op: The Mcu Manager operation.
    /// - parameter flags: Optional flags.
    /// - parameter len: Optional length.
    /// - parameter group: The group id for this command.
    /// - parameter seq: Optional sequence number.
    /// - parameter id: The subcommand id for the given group.
    public static func build(op: UInt8, flags: UInt8, len: UInt16, group: UInt16, seq: UInt8, id: UInt8) -> [UInt8] {
        return [op, flags, UInt8(len >> 4), UInt8(len & 0x0F), UInt8(group >> 4), UInt8(group & 0x0F), seq, id]
    }
}

extension McuMgrHeader: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        return "{op: \(op!), flags: \(flags!), length: \(length!), group: \(op!), seqNum=\(sequenceNumber!), commandId=\(commandId!)}"
    }
}

public enum McuMgrHeaderParseError: Error {
    case invalidSize(Int)
}

