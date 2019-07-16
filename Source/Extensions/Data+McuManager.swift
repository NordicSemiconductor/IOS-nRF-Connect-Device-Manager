/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CommonCrypto

internal extension Data {
    
    // MARK: - Convert data to and from types
    
    init<T>(from value: T) {
        var value = value
        self.init(buffer: UnsafeBufferPointer(start: &value, count: 1))
    }
    
    func to<T>(type: T.Type, offset: Int = 0) -> T {
        return self[offset..<self.count].withUnsafeBytes { $0.pointee }
    }
    
    func toReversed<T>(type: T.Type, offset: Int = 0) -> T {
        return Data(self.reversed()[offset..<self.count]).withUnsafeBytes { $0.pointee }
    }
    
    // MARK: - Hex Encoding
    
    struct HexEncodingOptions: OptionSet {
        public let rawValue: Int
        public static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
        public static let space = HexEncodingOptions(rawValue: 1 << 1)
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        var format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        if options.contains(.space) {
            format.append(" ")
        }
        return map { String(format: format, $0) }.joined()
    }
    
    // MARK: - Fragmentation
    
    func fragment(size: Int) -> [Data] {
        return stride(from: 0, to: self.count, by: size).map {
            Data(self[$0..<Swift.min($0 + size, self.count)])
        }
    }
    
    // MARK: - SHA 256
    
    func sha256() -> [UInt8] {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeBytes {
            _ = CC_SHA256($0, CC_LONG(count), &hash)
        }
        return hash
    }
}

