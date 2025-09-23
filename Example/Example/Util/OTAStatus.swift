//
//  OTAStatus.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 23/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import iOSOtaLibrary

// MARK: - OTAStatus

enum OTAStatus: CustomStringConvertible {
    case unsupported(_ error: Error?)
    case missingProjectKey(_ deviceInfo: DeviceInfoToken, _ error: Error)
    case supported(_ deviceInfo: DeviceInfoToken, _ projectKey: ProjectKey)
    
    var description: String {
        switch self {
        case .unsupported:
            return "UNSUPPORTED"
        case .missingProjectKey:
            return "MISSING PROJECT KEY"
        case .supported:
            return "SUPPORTED"
        }
    }
}
