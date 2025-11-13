//
//  ObservabilityDevice.swift
//  iOS-nRF-Memfault-Library
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 26/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - ObservabilityDevice

struct ObservabilityDevice {
    
    // MARK: Properties
    
    let uuidString: String
    var isConnected: Bool
    var isNotifying: Bool
    var isOnline: Bool
    var auth: ObservabilityAuth?
    
    // MARK: init
    
    init(uuidString: String) {
        self.uuidString = uuidString
        self.isConnected = false
        self.isNotifying = false
        self.isOnline = false
        self.auth = nil
    }
}
