/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

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
}
