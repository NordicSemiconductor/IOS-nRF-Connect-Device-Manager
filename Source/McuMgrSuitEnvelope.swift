//
//  McuMgrSuitEnvelope.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 11/12/23.
//

import Foundation
import SwiftCBOR

// MARK: - McuMgrSuitEnvelope

public struct McuMgrSuitEnvelope {
    
    public let digest: McuMgrSuitDigest
    public let data: Data
    
    // MARK: Init
    
    public init(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let validSize = data.count >= MemoryLayout<UInt8>.size * 2
        guard validSize, data[0] == 0xD8, data[1] == 0x6B,
              let cbor = try CBOR.decode(data.map({ $0 })) else {
            throw McuMgrSuitParseError.invalidDataSize
        }
        
        switch cbor {
        case .tagged(_, let cbor):
            self.digest = try McuMgrSuitDigest(cbor: cbor[0x2])
        default:
            throw McuMgrSuitParseError.digestMapNotFound
        }
        self.data = data
    }
    
    // MARK: API
    
    public func sizeString() -> String {
        return "\(data.count) bytes"
    }
}

// MARK: - McuMgrSuitDigest

public class McuMgrSuitDigest: CBORMappable {
    
    public var digests: [(type: Int, hash: Data)] = []
    
    // MARK: Init
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        switch cbor {
        case .byteString(let byteString):
            let innerCbor = try CBOR.decode(byteString)
            switch innerCbor {
            case .array(let digests):
                for digestCbor in digests {
                    guard case .byteString(let array) = digestCbor else {
                        throw McuMgrSuitParseError.digestArrayNotFound
                    }
                    let arrayCbor = try CBOR.decode(array)
                    switch arrayCbor {
                    case .array(let digest):
                        guard let type = digest[0].value as? Int else {
                            throw McuMgrSuitParseError.digestTypeNotFound
                        }
                        guard let value = digest[1].value as? [UInt8] else {
                            throw McuMgrSuitParseError.digestValueNotFound
                        }
                        // Fix for CBOR library when parsing negativeInt(s)
                        self.digests.append((type - 1, Data( value)))
                    default:
                        throw McuMgrImageParseError.insufficientData
                    }
                }
            default:
                throw McuMgrSuitParseError.digestArrayNotFound
            }
        default:
            throw McuMgrSuitParseError.unableToParseDigest
        }
    }
    
    // MARK: API
    
    public func hashString() -> String {
        var result = ""
        for digest in digests {
            let hashString = Data(digest.hash).hexEncodedString(options: .upperCase)
            result += "0x\(hashString)"
            guard digest.hash != digests.last?.hash else { continue }
            result += "\n"
        }
        return result
    }
}

// MARK: - McuMgrSuitParseError

public enum McuMgrSuitParseError: LocalizedError {
    case invalidDataSize
    case digestMapNotFound
    case digestArrayNotFound
    case digestTypeNotFound
    case digestValueNotFound
    case unableToParseDigest
    
    public var errorDescription: String? {
        switch self {
        case .invalidDataSize:
            return "The Data is not large enough to hold a SUIT Envelope / Digest"
        case .digestMapNotFound:
            return "The CBOR Map containing Digests could not be found or parsed."
        case .digestArrayNotFound:
            return "The CBOR Array containing the Digest could not be found."
        case .digestTypeNotFound:
            return "The Type of Digest value could not be found or parsed."
        case .digestValueNotFound:
            return "The Digest value could not be found or parsed."
        case .unableToParseDigest:
            return "The Digest CBOR Data was found, but could not be parsed or some essential elements were missing."
        }
    }
}
