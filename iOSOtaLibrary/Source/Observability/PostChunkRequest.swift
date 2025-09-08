//
//  PostChunkRequest.swift
//  iOS-nRF-Memfault-Library
//
//  Created by Dinesh Harjani on 19/8/22.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - PostChunkRequest

extension HTTPRequest {
    
    static func post(_ chunk: ObservabilityChunk, with chunkAuth: ObservabilityAuth) -> HTTPRequest {
        var httpRequest = HTTPRequest(url: chunkAuth.url)
        httpRequest.setMethod(HTTPMethod.POST)
        httpRequest.setHeaders([
            "Content-Type": "application/octet-stream",
            chunkAuth.authKey: chunkAuth.authValue
        ])
        httpRequest.setBody(chunk.data)
        return httpRequest
    }
}

// MARK: - MemfaultDeviceAuth

public struct ObservabilityAuth {
    
    let url: URL
    let authKey: String
    let authValue: String
}
