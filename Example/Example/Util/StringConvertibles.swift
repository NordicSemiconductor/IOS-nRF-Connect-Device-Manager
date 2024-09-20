/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */


import Foundation
import iOSMcuManagerLibrary

extension PeripheralState: @retroactive CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .connecting:
            return "CONNECTING..."
        case .initializing:
            return "INITIALIZING..."
        case .connected:
            return "CONNECTED"
        case .disconnecting:
            return "DISCONNECTING..."
        case .disconnected:
            return "DISCONNECTED"
        }
    }
}

