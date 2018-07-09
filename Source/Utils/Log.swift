/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

class Log {
    
    enum Level: String {
        case verbose = "V/"
        case debug = "D/"
        case info = "I/"
        case warn = "W/"
        case error = "E/"
    }
    
    static func log(_ level: Level, tag: String, msg: String) {
        print("\(level.rawValue)\(tag): \(msg)")
    }
    
    static func v(_ tag: String, msg: String) {
        log(.verbose, tag: tag, msg: msg)
    }
    
    static func d(_ tag:String, msg: String) {
        log(.debug, tag: tag, msg: msg)
    }
    
    static func i(_ tag: String, msg: String) {
        log(.info, tag: tag, msg: msg)
    }
    
    static func w(_ tag: String, msg: String) {
        log(.warn, tag: tag, msg: msg)
    }
    
    static func e(_ tag: String, msg: String) {
        log(.error, tag: tag, msg: msg)
    }
    
    static func e(_ tag: String, error: Error) {
        log(.error, tag: tag, msg: String(describing: error))
    }
}
