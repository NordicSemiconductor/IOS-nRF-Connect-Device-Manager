//
//  MemfaultDevice.swift
//  iOS-nRF-Memfault-Library
//
//  Created by Dinesh Harjani on 26/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - MemfaultDevice

struct ObservabilityDevice {
    
    // MARK: Properties
    
    let uuidString: String
    var isConnected: Bool
    var isNotifying: Bool
    var isStreaming: Bool
    var auth: ObservabilityAuth?
    
    // MARK: init
    
    init(uuidString: String) {
        self.uuidString = uuidString
        self.isConnected = false
        self.isNotifying = false
        self.isStreaming = false
        self.auth = nil
    }
}
