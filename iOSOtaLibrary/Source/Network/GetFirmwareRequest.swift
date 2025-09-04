//
//  GetFirmwareRequest.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 3/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

extension HTTPRequest {
    
    static func getLatestFirmware(token: DeviceInfoToken, key: ProjectKey) -> HTTPRequest? {
        let parameters: [String: String] = [
            "device_id": token.deviceSerialNumber,
            "hardware_version": token.hardwareVersion,
            "software_type": token.softwareType,
            "current_version": token.currentVersion
        ]
        // https://api.memfault.com/api/v0/releases/latest
        guard var request = HTTPRequest(scheme: .https, host: "api.memfault.com", path: "/api/v0/releases/latest", parameters: parameters) else {
            return nil
        }
        request.setMethod(HTTPMethod.GET)
        request.setHeaders([
            "Accept": "application/json",
            "Memfault-Project-Key": key.authKey
        ])
        return request
    }
}
