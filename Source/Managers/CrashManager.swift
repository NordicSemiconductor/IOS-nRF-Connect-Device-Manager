/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import SwiftCBOR

public class CrashManager: McuManager {
    
    //**************************************************************************
    // MARK: Constants
    //**************************************************************************

    // Mcu Crash Manager ids.
    let ID_TEST = UInt8(0)
    
    public enum CrashTest: String {
        case div0 = "div0"
        case jump0 = "jump0"
        case ref0 = "ref0"
        case assert = "assert"
        case wdog = "wdog"
    }
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: .crash, transporter: transporter)
    }

    //**************************************************************************
    // MARK: Commands
    //**************************************************************************

    /// Run a crash test on a device.
    ///
    /// - parameter crash: The crash test to run.
    /// - parameter callback: The response callback.
    public func test(crash: CrashTest, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        let payload: [String:CBOR] = ["t": CBOR.utf8String(crash.rawValue)]
        send(op: .write, commandId: ID_TEST, payload: payload, callback: callback)
    }
}
