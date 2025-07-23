/*
 * Copyright (c) 2025 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Manager class for handling Memfault OTA update checks and downloads
public class MemfaultOTAManager {
    
    // MARK: - Types
    
    public struct UpdateInfo {
        public let version: String
        public let downloadUrl: URL
        public let releaseNotes: String?
    }
    
    public enum OTAError: LocalizedError {
        case invalidProjectKey
        case networkError(Error)
        case invalidResponse(String?)
        case noUpdateAvailable
        
        public var errorDescription: String? {
            switch self {
            case .invalidProjectKey:
                return "Invalid or missing Memfault project key"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse(let details):
                if let details = details, !details.isEmpty {
                    return "Memfault API Error: \(details)"
                } else {
                    return "Invalid response from Memfault API"
                }
            case .noUpdateAvailable:
                return "No update available"
            }
        }
    }
    
    // MARK: - Properties
    
    private let projectKey: String
    private let hardwareVersion: String
    private let softwareType: String
    private var deviceSerial: String?
    private let session = URLSession.shared
    
    private var updateCache: [String: UpdateInfo] = [:]
    private var checkingVersions: Set<String> = []
    
    // MARK: - Initialization
    
    public init(projectKey: String, hardwareVersion: String = "nrf53", softwareType: String = "main", deviceSerial: String? = nil) {
        self.projectKey = projectKey
        self.hardwareVersion = hardwareVersion
        self.softwareType = softwareType
        self.deviceSerial = deviceSerial
    }
    
    // MARK: - Public Methods
    
    /// Check for available firmware updates
    public func checkForUpdate(currentVersion: String, completion: @escaping (Result<UpdateInfo?, OTAError>) -> Void) {
        guard !projectKey.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(.invalidProjectKey))
            }
            return
        }
        
        // Prevent duplicate checks for the same version
        guard !checkingVersions.contains(currentVersion) else {
            print("MemfaultOTAManager: Already checking for updates for version \(currentVersion)")
            return
        }
        checkingVersions.insert(currentVersion)
        
        // Check cache first
        let cacheKey = "\(hardwareVersion)-\(softwareType)-\(currentVersion)"
        if let cachedUpdate = updateCache[cacheKey] {
            checkingVersions.remove(currentVersion)
            DispatchQueue.main.async {
                completion(.success(cachedUpdate))
            }
            return
        }
        
        var urlComponents = URLComponents(string: "https://api.memfault.com/api/v0/releases/latest")!
        urlComponents.queryItems = [
            URLQueryItem(name: "hardware_version", value: hardwareVersion),
            URLQueryItem(name: "software_type", value: softwareType),
            URLQueryItem(name: "current_version", value: currentVersion)
        ]
        
        if let serial = deviceSerial {
            urlComponents.queryItems?.append(URLQueryItem(name: "device_serial", value: serial))
        }
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue(projectKey, forHTTPHeaderField: "Memfault-Project-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        session.dataTask(with: request) { [weak self] data, response, error in
            defer {
                self?.checkingVersions.remove(currentVersion)
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(.networkError(error)))
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse("No HTTP response")))
                }
                return
            }
            
            // Log response for debugging
            print("MemfaultOTAManager: HTTP Status: \(httpResponse.statusCode)")
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse("No data received")))
                }
                return
            }
            
            // Parse JSON response
            do {
                if httpResponse.statusCode == 204 {
                    // No update available
                    self?.updateCache[cacheKey] = nil
                    DispatchQueue.main.async {
                        completion(.success(nil))
                    }
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    let errorBody = String(data: data, encoding: .utf8)
                    print("MemfaultOTAManager: Error response: \(errorBody ?? "none")")
                    
                    // Try to parse error response for better error messages
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        DispatchQueue.main.async {
                            completion(.failure(.invalidResponse(message)))
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(.invalidResponse(errorBody)))
                        }
                    }
                    return
                }
                
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                // Get version from top level
                guard let version = json?["version"] as? String else {
                    DispatchQueue.main.async {
                        completion(.failure(.invalidResponse("Invalid JSON structure - missing 'version'")))
                    }
                    return
                }
                
                // Get artifacts array
                guard let artifacts = json?["artifacts"] as? [[String: Any]] else {
                    DispatchQueue.main.async {
                        completion(.failure(.invalidResponse("Invalid JSON structure - missing 'artifacts' array")))
                    }
                    return
                }
                
                // Get first artifact with URL
                guard let artifact = artifacts.first,
                      let urlString = artifact["url"] as? String,
                      let url = URL(string: urlString) else {
                    DispatchQueue.main.async {
                        completion(.failure(.invalidResponse("Invalid JSON structure - missing artifact URL")))
                    }
                    return
                }
                
                // Get release notes from 'notes' field
                let releaseNotes = json?["notes"] as? String
                let updateInfo = UpdateInfo(version: version, downloadUrl: url, releaseNotes: releaseNotes)
                
                // Cache the result
                self?.updateCache[cacheKey] = updateInfo
                
                DispatchQueue.main.async {
                    completion(.success(updateInfo))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse("JSON parsing error: \(error)")))
                }
            }
        }.resume()
    }
    
    /// Download firmware from the provided URL
    public func downloadFirmware(from url: URL, progress: @escaping (Double) -> Void, completion: @escaping (Result<Data, Error>) -> Void) {
        var observation: NSKeyValueObservation?
        
        let task = session.downloadTask(with: url) { localURL, response, error in
            observation?.invalidate()
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let localURL = localURL else {
                completion(.failure(OTAError.invalidResponse("No file downloaded")))
                return
            }
            
            do {
                let data = try Data(contentsOf: localURL)
                completion(.success(data))
            } catch {
                completion(.failure(error))
            }
        }
        
        // Observe download progress
        observation = task.observe(\.countOfBytesReceived) { task, _ in
            let totalBytes = task.countOfBytesExpectedToReceive
            if totalBytes > 0 {
                let downloadProgress = Double(task.countOfBytesReceived) / Double(totalBytes)
                DispatchQueue.main.async {
                    progress(downloadProgress)
                }
            }
        }
        
        task.resume()
    }
}