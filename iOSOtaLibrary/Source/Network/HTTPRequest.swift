//
//  HTTPRequest.swift
//  iOS-Common-Libraries
//
//  Created by Dinesh Harjani on 26/2/21.
//

import Foundation

// MARK: - HTTPRequest

public typealias HTTPRequest = URLRequest

public extension HTTPRequest {
    
    // MARK: - Init
    
    init?(scheme: HTTPScheme = .https, host: String, path: String, parameters: [String: String]? = nil) {
        var components = URLComponents()
        components.scheme = scheme.rawValue
        components.host = host
        components.path = path
        components.queryItems = parameters?.map { key, value in
            URLQueryItem(name: key, value: value)
        }
        
        guard let url = components.url else { return nil }
        self.init(url: url)
    }
    
    // MARK: - API
    
    mutating func setMethod(_ httpMethod: HTTPMethod) {
        self.httpMethod = httpMethod.rawValue
    }
    
    mutating func setHeaders(_ headers: [String : String]) {
        for (field, value) in headers {
            addValue(value, forHTTPHeaderField: field)
        }
    }
    
    mutating func setBody(_ data: Data) {
        httpBody = data
    }
}

// MARK: - Scheme

public enum HTTPScheme: String, RawRepresentable {
    
    case wss, https
}

// MARK: - Method

public enum HTTPMethod: String, RawRepresentable {
    
    case GET, POST, DELETE
}

// MARK: - HTTPResponse

public protocol HTTPResponse: Codable {
    
    var success: Bool { get }
    var error: String? { get }
}
