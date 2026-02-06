//
//  PostChunkRequest.swift
//  iOS-nRF-Memfault-Library
//
//  Created by Dinesh Harjani on 19/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import iOS_Common_Libraries

// MARK: - PostChunkRequest

extension HTTPRequest {

    static func post(_ chunk: ObservabilityChunk, with chunkAuth: ObservabilityAuth) -> HTTPRequest {
        var httpRequest = HTTPRequest(url: chunkAuth.url)
        httpRequest.setMethod(HTTPMethod.POST)
        httpRequest.setHeaders([
            "Content-Type": "application/octet-stream",
            chunkAuth.authKey: chunkAuth.authValue,
            "User-Agent": otaLibraryUserAgent()
        ])
        httpRequest.setBody(chunk.data)
        return httpRequest
    }
}

extension HTTPRequest {

    static func otaLibraryUserAgent() -> String {
        let bundle = Bundle(for: OTAManager.self)
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Device Manager"
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let darwinVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Get CFNetwork version from the system
        let cfNetworkVersion = Bundle(identifier: "com.apple.CFNetwork")?
            .object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "Unknown"

        return "\(appName) \(appVersion)/\(buildNumber) CFNetwork/\(cfNetworkVersion) Darwin/\(darwinVersion)"
    }
}

// MARK: - ObservabilityAuth

public struct ObservabilityAuth {

    let url: URL
    let authKey: String
    let authValue: String
}
