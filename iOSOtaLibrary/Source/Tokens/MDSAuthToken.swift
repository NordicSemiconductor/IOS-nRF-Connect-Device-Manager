//
//  MDSAuthToken.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 3/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - MDSAuthToken

public struct MDSAuthToken {
    
    // MARK: Properties
    
    public let authKey: String
    
    // MARK: init
    
    public init?(_ authValue: String) {
        guard let key = authValue.split(separator: ":").last else { return nil }
        self.authKey = String(key)
    }
}
