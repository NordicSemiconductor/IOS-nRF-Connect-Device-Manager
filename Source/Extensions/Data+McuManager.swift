/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public extension Data {
    
    // MARK: - Convert data to and from types
    
    public init<T>(from value: T) {
        var value = value
        self.init(buffer: UnsafeBufferPointer(start: &value, count: 1))
    }
    
    public func to<T>(type: T.Type, offset: Int = 0) -> T {
        return self[offset..<self.count].withUnsafeBytes { $0.pointee }
    }
    
    public func toReversed<T>(type: T.Type, offset: Int = 0) -> T {
        return Data(self.reversed()[offset..<self.count]).withUnsafeBytes { $0.pointee }
    }
    
    // MARK: - Hex Encoding
    
    public struct HexEncodingOptions: OptionSet {
        public let rawValue: Int
        public static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
        public static let space = HexEncodingOptions(rawValue: 1 << 1)
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    public func hexEncodedString(options: HexEncodingOptions = []) -> String {
        var format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        if options.contains(.space) {
            format.append(" ")
        }
        return map { String(format: format, $0) }.joined()
    }
    
    // MARK: - Fragmentation
    
    public func fragment(size: Int) -> [Data] {
        return stride(from: 0, to: self.count, by: size).map {
            Data(self[$0..<Swift.min($0 + size, self.count)])
        }
    }
}

