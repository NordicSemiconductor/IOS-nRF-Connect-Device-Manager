//
//  ProjectKey.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 3/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - ProjectKey

public struct ProjectKey {
    
    // MARK: Properties
    
    public let authKey: String
    
    // MARK: init
    
    public init?(authValue: String) {
        guard let key = authValue.split(separator: ":").last else { return nil }
        self.init(String(key))
    }
    
    public init(_ key: String) {
        self.authKey = String(key)
    }
}
