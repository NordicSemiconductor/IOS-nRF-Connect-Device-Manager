//
//  GetFirmwareRequest.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 3/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - getLatestFirmware

extension HTTPRequest {
    
    static func getLatestReleaseInfo(token: DeviceInfoToken, key: ProjectKey) -> HTTPRequest? {
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

// MARK: - LatestReleaseInfo

public struct LatestReleaseInfo: Codable {
    
    // MARK: Properties
    
    let id: Int
    let createdDate: Date
    let version: String
    let revision: String
    let mustPassThrough: Bool
    let notes: String
    let artifacts: [ReleaseArtifact]
    let reason: String
    let isDelta: Bool
}

// MARK: - ReleaseArtifact

public struct ReleaseArtifact: Codable {
    
    // MARK: Properties
    
    let id: Int
    let createdDate: Date
    let type: String
    let hardwareVersion: String
    let filename: String
    let fileSize: Int
    let url: String
    let md5: String
    let sha1: String
    let sha256: String
    
    // MARK: URL
    
    public func releaseURL() -> URL? {
        return URL(string: url)
    }
}
