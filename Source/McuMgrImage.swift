/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public class McuMgrImage {
    
    public static let IMG_HASH_LEN = 32
    
    public let header: McuMgrImageHeader
    public let tlv: McuMgrImageTlv
    public let data: Data
    public let hash: Data
    
    public init(data: Data) throws {
        self.data = data
        self.header = try McuMgrImageHeader(data: data)
        self.tlv = try McuMgrImageTlv(data: data, imageHeader: header)
        self.hash = tlv.hash
    }
}

public class McuMgrImageHeader {
    
    public static let IMG_HEADER_LEN = 24
    
    public static let IMG_HEADER_MAGIC: UInt32 = 0x96f3b83d
    public static let IMG_HEADER_MAGIC_V1: UInt32 = 0x96f3b83c
    
    public static let MAGIC_OFFSET = 0
    public static let LOAD_ADDR_OFFSET = 4
    public static let HEADER_SIZE_OFFSET = 8
    public static let IMAGE_SIZE_OFFSET = 12
    public static let FLAGS_OFFSET = 16
    
    public let magic: UInt32
    public let loadAddr: UInt32
    public let headerSize: UInt16
    // __pad1: UInt16
    public let imageSize: UInt32
    public let flags: UInt32
    public let version: McuMgrImageVersion
    // __pad2 UInt16
    
    public init(data: Data) throws {
        magic = data.read(offset: McuMgrImageHeader.MAGIC_OFFSET)
        loadAddr = data.read(offset: McuMgrImageHeader.LOAD_ADDR_OFFSET)
        headerSize = data.read(offset: McuMgrImageHeader.HEADER_SIZE_OFFSET)
        imageSize = data.read(offset: McuMgrImageHeader.IMAGE_SIZE_OFFSET)
        flags = data.read(offset: McuMgrImageHeader.FLAGS_OFFSET)
        version = McuMgrImageVersion(data: data)
        if magic != McuMgrImageHeader.IMG_HEADER_MAGIC && magic != McuMgrImageHeader.IMG_HEADER_MAGIC_V1 {
            throw McuMgrImageParseError.invalidHeaderMagic
        }
    }
    
    public func isLegacy() -> Bool {
        return magic == McuMgrImageHeader.IMG_HEADER_MAGIC_V1
    }
}

public class McuMgrImageVersion {
    
    public static let VERSION_OFFSET = 20
    
    public let major: UInt8
    public let minor: UInt8
    public let revision: UInt16
    public let build: UInt32
    
    public init(data: Data, offset: Int = VERSION_OFFSET) {
        major = data[offset]
        minor = data[offset + 1]
        revision = data.read(offset: offset + 2)
        build = data.read(offset: offset + 4)
    }
}

public class McuMgrImageTlv {
    
    public static let IMG_TLV_SHA256: UInt8 = 0x10
    public static let IMG_TLV_SHA256_V1: UInt8 = 0x01
    public static let IMG_TLV_INFO_MAGIC: UInt16 = 0x6907
    
    public var tlvInfo: McuMgrImageTlvInfo?
    public var trailerTlvEntries: [McuMgrImageTlvTrailerEntry]
    
    public let hash: Data
    
    public init(data: Data, imageHeader: McuMgrImageHeader) throws {
        var offset = Int(imageHeader.headerSize) + Int(imageHeader.imageSize)
        let end = data.count
        
        // Parse the tlv info header (Not included in legacy version).
        if !imageHeader.isLegacy() {
            try tlvInfo = McuMgrImageTlvInfo(data: data, offset: offset)
            offset += McuMgrImageTlvInfo.SIZE
        }
        
        // Parse each tlv entry.
        trailerTlvEntries = [McuMgrImageTlvTrailerEntry]()
        var hashEntry: McuMgrImageTlvTrailerEntry?
        while offset + McuMgrImageTlvTrailerEntry.MIN_SIZE < end {
            let tlvEntry = try McuMgrImageTlvTrailerEntry(data: data, offset: offset)
            trailerTlvEntries.append(tlvEntry)
            // Set the hash if this entry's type matches the hash's type
            if imageHeader.isLegacy() && tlvEntry.type == McuMgrImageTlv.IMG_TLV_SHA256_V1 ||
                !imageHeader.isLegacy() && tlvEntry.type == McuMgrImageTlv.IMG_TLV_SHA256 {
                hashEntry = tlvEntry
            }
            
            // Increment offset.
            offset += tlvEntry.size
        }
        
        // Set the hash. If not found, throw an error.
        if let hashEntry = hashEntry {
            hash = hashEntry.value
        } else {
            throw McuMgrImageParseError.hashNotFound
        }
    }
}

/// Represents the header which starts immediately after the image data and
/// precedes the image trailer TLV.
public class McuMgrImageTlvInfo {
    
    public static let SIZE = 4
    
    public let magic: UInt16
    public let total: UInt16
    
    public init(data: Data, offset: Int) throws {
        magic = data.read(offset: offset)
        total = data.read(offset: offset + 2)
        if magic != McuMgrImageTlv.IMG_TLV_INFO_MAGIC {
            throw McuMgrImageParseError.invalidTlvInfoMagic
        }
    }
}

/// Represents an entry in the image TLV trailer.
public class McuMgrImageTlvTrailerEntry {
    
    /// The minimum size of the TLV entry (length = 0).
    public static let MIN_SIZE = 4
    
    public let type: UInt8
    // __pad: UInt8
    public let length: UInt16
    public let value: Data
    
    /// Size of the entire TLV entry in bytes.
    public let size: Int
    
    public init(data: Data, offset: Int) throws {
        guard offset + McuMgrImageTlvTrailerEntry.MIN_SIZE < data.count else {
            throw McuMgrImageParseError.insufficientData
        }
        
        var offset = offset
        type = data[offset]
        offset += 2 // Increment offset and account for extra byte of padding.
        length = data.read(offset: offset)
        offset += 2 // Move offset past length.
        value = data[Int(offset)..<Int(offset + Int(length))]
        size = McuMgrImageTlvTrailerEntry.MIN_SIZE + Int(length)
    }
}

public enum McuMgrImageParseError: Error {
    case invalidHeaderMagic
    case invalidTlvInfoMagic
    case insufficientData
    case hashNotFound
}

extension McuMgrImageParseError: LocalizedError {
    
    public var errorDescription: String? {
        switch self {
        case .invalidHeaderMagic:
            return "Invalid Header Magic Number. Are You Trying to DFU an Image That Has Not Been Properly Signed?"
        case .invalidTlvInfoMagic:
            return "Invalid TLV Info Magic Number. Are You Trying to DFU an Image That Has Not Been Properly Signed Again?"
        case .insufficientData:
            return "Insufficient Data."
        case .hashNotFound:
            return "Hash Not Found."
        }
    }
    
}
