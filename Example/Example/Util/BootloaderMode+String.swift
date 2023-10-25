/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */


import Foundation
import iOSMcuManagerLibrary

extension BootloaderInfoResponse.Mode {
    
    var text: String {
        switch self {
        case .SingleApplication: return "Single application"
        case .SwapNoScratch: return "Swap without scratch"
        case .SwapUsingScratch: return "Swap with scratch"
        case .RAMLoader: return "RAM loader"
        case .DirectXIPNoRevert: return "Direct-XIP without revert"
        case .DirectXIPWithRevert: return "Direct-XIP with revert"
        case .Overwrite: return "Overwrite"
        default: return "Unknown"
        }
    }
    
}
