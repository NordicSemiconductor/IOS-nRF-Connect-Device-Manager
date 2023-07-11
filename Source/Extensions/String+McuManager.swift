/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

// MARK: - String

internal extension String {
    
    func replaceFirst(of pattern:String, with replacement:String) -> String {
        if let range = self.range(of: pattern) {
            return self.replacingCharacters(in: range, with: replacement)
        } else {
            return self
        }
    }
    
    func replaceLast(of pattern:String, with replacement:String) -> String {
        if let range = self.range(of: pattern, options: String.CompareOptions.backwards) {
            return self.replacingCharacters(in: range, with: replacement)
        } else {
            return self
        }
    }
    
    func inserting(separator: String, every n: Int) -> String {
        var result: String = ""
        let characters = Array(self)
        stride(from: 0, to: characters.count, by: n).forEach {
            result += String(characters[$0..<min($0 + n, characters.count)])
            if $0 + n < characters.count {
                result += separator
            }
        }
        return result
    }
}

// MARK: - StringInterpolation

internal extension String.StringInterpolation {

    /**
     Fix for SwiftLint warning when printing an Optional value.
     */
    mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T?) {
        appendInterpolation(value ?? "nil" as CustomStringConvertible)
    }
}
