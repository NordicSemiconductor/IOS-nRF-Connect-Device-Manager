/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */


import Foundation
import iOSMcuManagerLibrary

extension PeripheralState: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .connecting:    return "CONNECTING..."
        case .initializing:  return "INITIALIZING..."
        case .connected:     return "CONNECTED"
        case .disconnecting: return "DISCONNECTING..."
        case .disconnected:  return "DISCONNECTED"
        }
    }
    
}

extension BootloaderInfoResponse.Mode: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .singleApplication:
            return "Single application"
        case .swapUsingScratch:
            return "Swap using scratch partition"
        case .overwrite:
            return "Overwrite (upgrade-only)"
        case .swapNoScratch:
            return "Swap without scratch"
        case .directXIPNoRevert:
            return "Direct-XIP without revert"
        case .directXIPWithRevert:
            return "Direct-XIP with revert"
        case .RAMLoader:
            return "RAM Loader"
        }
    }
    
}

