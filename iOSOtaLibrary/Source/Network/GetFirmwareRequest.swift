//
//  GetFirmwareRequest.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 3/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

internal struct GetFirmwareRequest {
    
    private var urlRequest: URLRequest
    
    // MARK: init
    
    private init?() {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.memfault.com"
        components.path = "/api/v0/releases/latest"
//        components.queryItems = parameters?.map { key, value in
//            URLQueryItem(name: key, value: value)
//        }
    
        guard let url = components.url else { return nil }
        self.urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
//        for (field, value) in headers {
//        //        addValue(value, forHTTPHeaderField: field)
//            }
    }
}
