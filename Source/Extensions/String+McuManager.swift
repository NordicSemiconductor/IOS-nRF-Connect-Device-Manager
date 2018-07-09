/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public extension String {
    
    public func replaceFirst(of pattern:String, with replacement:String) -> String {
        if let range = self.range(of: pattern) {
            return self.replacingCharacters(in: range, with: replacement)
        } else {
            return self
        }
    }
    
    public func replaceLast(of pattern:String, with replacement:String) -> String {
        if let range = self.range(of: pattern, options: String.CompareOptions.backwards) {
            return self.replacingCharacters(in: range, with: replacement)
        } else {
            return self
        }
    }
}
