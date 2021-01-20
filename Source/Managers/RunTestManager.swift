/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import SwiftCBOR

public class RunTestManager: McuManager {
    override class var TAG: McuMgrLogCategory { .runTest }
    
    //**************************************************************************
    // MARK: Run Constants
    //**************************************************************************

    // Mcu Run Test Manager ids.
    let ID_TEST = UInt8(0)
    let ID_LIST = UInt8(1)
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(transporter: McuMgrTransport) {
        super.init(group: McuMgrGroup.run, transporter: transporter)
    }
    
    //**************************************************************************
    // MARK: Run Commands
    //**************************************************************************

    /// Run tests on a device.
    ///
    /// The device will run the test specified in the 'name' or all tests if not
    /// specified.
    ///
    /// - parameter name: The name of the test to run. If left out, all tests
    ///   will be run.
    /// - parameter token: The optional token to returned in the response.
    /// - parameter callback: The response callback.
    public func test(name: String? = nil, token: String? = nil, callback: @escaping McuMgrCallback<McuMgrResponse>) {
        var payload: [String:CBOR] = [:]
        if let name = name {
            payload.updateValue(CBOR.utf8String(name), forKey: "testname")
        }
        if let token = token {
            payload.updateValue(CBOR.utf8String(token), forKey: "token")
        }
        send(op: .write, commandId: ID_TEST, payload: payload, callback: callback)
    }

    /// List the tests on a device.
    ///
    /// - parameter callback: The response callback.
    public func list(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .read, commandId: ID_LIST, payload: nil, callback: callback)
    }
    
}
