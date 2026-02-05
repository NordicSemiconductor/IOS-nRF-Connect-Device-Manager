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

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let userAgent = "nRF Device Manager/\(appVersion)"

        httpRequest.setHeaders([
            "Content-Type": "application/octet-stream",
            chunkAuth.authKey: chunkAuth.authValue,
            "User-Agent": userAgent
        ])
        httpRequest.setBody(chunk.data)
        return httpRequest
    }
}

// MARK: - ObservabilityAuth

public struct ObservabilityAuth {

    let url: URL
    let authKey: String
    let authValue: String
}
