//
//  Data+McuManager.swift
//  Example
//
//  Created by Brian Giori on 2/20/19.
//  Copyright © 2019 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

extension Data {
    
    internal struct HexEncodingOptions: OptionSet {
        public let rawValue: Int
        public static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
        public static let space = HexEncodingOptions(rawValue: 1 << 1)
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    internal func hexEncodedString(options: HexEncodingOptions = []) -> String {
        var format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        if options.contains(.space) {
            format.append(" ")
        }
        return map { String(format: format, $0) }.joined()
    }
    
}
