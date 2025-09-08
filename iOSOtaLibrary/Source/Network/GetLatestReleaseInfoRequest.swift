//
//  GetLatestReleaseInfoRequest.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 3/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - getLatestReleaseInfo

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
    
    public let id: Int
    public let createdDate: Date
    public let version: String
    public let revision: String
    public let mustPassThrough: Bool
    public let notes: String
    public let artifacts: [ReleaseArtifact]
    public let reason: String
    public let isDelta: Bool
    
    public func latestRelease() -> ReleaseArtifact {
        return artifacts
            .first!
    }
}

// MARK: - ReleaseArtifact

public struct ReleaseArtifact: Codable {
    
    // MARK: Properties
    
    public let id: Int
    public let createdDate: Date
    public let type: String
    public let hardwareVersion: String
    public let filename: String
    public let fileSize: Int
    public let url: String
    public let md5: String
    public let sha1: String
    public let sha256: String
    
    // MARK: sizeString()
    
    public func sizeString() -> String {
        guard #available(iOS 16.0, macCatalyst 16.0, macOS 13.0, *) else {
            return "\(fileSize) bytes"
        }
        let fileSizeMeasurement = Measurement<UnitInformationStorage>(value: Double(fileSize), unit: .bytes)
        return fileSizeMeasurement.formatted(.byteCount(style: .file))
    }
    
    // MARK: releaseURL()
    
    public func releaseURL() -> URL? {
        return URL(string: url)
    }
}
