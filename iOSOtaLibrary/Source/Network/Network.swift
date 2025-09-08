//
//  Network.swift
//  iOS-Common-Libraries
//
//  Created by Dinesh Harjani on 26/2/21.
//

import Foundation
import Combine
import SwiftUI
import SystemConfiguration
import os

// MARK: - Network

public final class Network {
    
    // MARK: - Properties
    
    private let log = OSLog(subsystem: "iOSOtaLibrary", category: "network")
    private lazy var session = URLSession(configuration: .default)
    
    private var reachability: SCNetworkReachability?
    
    // MARK: Public Init
    
    public init(_ host: String) {
        reachability = SCNetworkReachabilityCreateWithName(nil, host)
    }
}

// MARK: - API

public extension Network {
    
    // MARK: - Reachability
    
    func getReachabilityPublisher() -> AnyPublisher<Bool, Error> {
        return CurrentValueSubject<Bool, Error>(isReachable())
            .tryMap { isReachable in
                guard isReachable else {
                    throw URLError(.cannotFindHost)
                }
                return true
            }
            .eraseToAnyPublisher()
    }
    
    func isReachable() -> Bool {
        guard let reachability else {
            os_log("%@", log: log, type: .error, "\(#function): Nil reachability property.")
            return false
        }
        
        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability, &flags)

        let isReachable = flags.contains(.reachable)
        let connectionRequired = flags.contains(.connectionRequired)
        let canConnectAutomatically = flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
        let canConnectWithoutIntervention = canConnectAutomatically && !flags.contains(.interventionRequired)
        let result = isReachable && (!connectionRequired || canConnectWithoutIntervention)
        os_log("%@", log: log, type: .debug, "\(#function): \(result)")
        return isReachable && (!connectionRequired || canConnectWithoutIntervention)
    }
    
    // MARK: - HTTPRequest
    
    func perform(_ request: HTTPRequest) -> AnyPublisher<Data, Error> {
        let sessionRequestPublisher = session.dataTaskPublisher(for: request)
            .tryMap() { [log] element -> Data in
                #if DEBUG
                os_log("%@", log: log, type: .debug, "\(element.response)")
                #endif
                
                guard let httpResponse = element.response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                switch httpResponse.statusCode {
                case 200...299: // Success.
                    return element.data
                case 401:
                    throw URLError(.userAuthenticationRequired)
                default: // Assume Error.
                    if let responseDataAsString = String(data: element.data, encoding: .utf8) {
                        #if DEBUG
                        os_log("%@", log: log, type: .debug, "\(request): \(responseDataAsString)")
                        #endif
                        throw URLError(.cannotParseResponse)
                    } else {
                        throw URLError(.badServerResponse)
                    }
                }
            }
            .eraseToAnyPublisher()
        
        return getReachabilityPublisher()
            .flatMap { _ -> AnyPublisher<Data, Error> in
                return sessionRequestPublisher
            }
            .eraseToAnyPublisher()
    }
    
    func perform<T: Codable>(_ request: HTTPRequest, responseType: T.Type = T.self) -> AnyPublisher<T, Error> {
        return perform(request)
            .flatMap { data -> AnyPublisher<T, Error> in
                let decoder = JSONDecoder()
                if let response = try? decoder.decode(T.self, from: data) {
                    return Just(response).setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }

                do {
                    let errorResponse = try decoder.decode(BasicHTTPResponse.self, from: data)
                    return Fail(error: errorResponse)
                        .eraseToAnyPublisher()
                } catch (let error) {
                    guard let stringResponse = String(data: data, encoding: .utf8) else {
                        return Fail(error: error)
                            .eraseToAnyPublisher()
                    }
                    if stringResponse.contains("session expired") {
                        return Fail(error: URLError(.userAuthenticationRequired))
                            .eraseToAnyPublisher()
                    } else  {
                        return Fail(error: BasicHTTPResponse(success: false, error: "Unknown Server Error Received."))
                            .eraseToAnyPublisher()
                    }
                }
            }
            .tryCatch { error -> AnyPublisher<T, Error> in
                if let urlError = error as? URLError, urlError.errorCode == -1200 {
                    return Fail(error: URLError(.appTransportSecurityRequiresSecureConnection))
                        .eraseToAnyPublisher()
                }
                throw error
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - BasicHTTPResponse

public struct BasicHTTPResponse: HTTPResponse, LocalizedError {
    
    public let success: Bool
    public let error: String?
    
    public var errorDescription: String? { error }
    public var recoverySuggestion: String? { error }
    public var helpAnchor: String? { "Try Postman or ask Roshee for help." }
}
