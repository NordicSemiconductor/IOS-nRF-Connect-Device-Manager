//
//  NRFCloudOTAManager.swift
//  nRF Connect Device Manager
//
//  OTA update manager for nRF Cloud (Memfault) integration
//

import Foundation

class NRFCloudOTAManager {
    struct UpdateInfo {
        let version: String?
        let url: String?
        let size: Int?
        let releaseNotes: String?
    }
    
    enum OTAError: Error, Equatable {
        case invalidResponse
        case noUpdateAvailable
        case networkError(Error)
        
        static func == (lhs: OTAError, rhs: OTAError) -> Bool {
            switch (lhs, rhs) {
            case (.invalidResponse, .invalidResponse):
                return true
            case (.noUpdateAvailable, .noUpdateAvailable):
                return true
            case (.networkError(_), .networkError(_)):
                return true  // We consider any network errors as equal for simplicity
            default:
                return false
            }
        }
    }
    
    func checkForUpdate(
        projectKey: String,
        deviceId: String,
        hardwareVersion: String,
        softwareType: String,
        currentVersion: String,
        extraQuery: String?,
        completion: @escaping (Result<UpdateInfo, Error>) -> Void
    ) {
        // Build the API URL
        var components = URLComponents(string: "https://api.memfault.com/api/v0/releases/latest")!
        components.queryItems = [
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "hardware_version", value: hardwareVersion),
            URLQueryItem(name: "software_type", value: softwareType),
            URLQueryItem(name: "current_version", value: currentVersion)
        ]
        
        if let extra = extraQuery {
            components.queryItems?.append(URLQueryItem(name: "extra", value: extra))
        }
        
        var request = URLRequest(url: components.url!)
        request.setValue(projectKey, forHTTPHeaderField: "Memfault-Project-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        print("[NRFCloud] API Request URL: \(components.url!)")
        print("[NRFCloud] Using Project Key: \(projectKey)")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(OTAError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(OTAError.invalidResponse))
                return
            }
            
            print("[NRFCloud] API Response Status: \(httpResponse.statusCode)")
            
            // Check status code
            if httpResponse.statusCode == 204 {
                // 204 No Content means no update available
                print("[NRFCloud] No update available (204 No Content)")
                completion(.failure(OTAError.noUpdateAvailable))
                return
            } else if httpResponse.statusCode != 200 {
                if httpResponse.statusCode == 401 {
                    print("[NRFCloud] ERROR 401: Unauthorized - Project key may be incorrect")
                }
                if let data = data, let errorText = String(data: data, encoding: .utf8) {
                    print("[NRFCloud] Error response body: \(errorText)")
                }
                let error = NSError(
                    domain: "NRFCloudOTA",
                    code: httpResponse.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)",
                        "statusCode": httpResponse.statusCode
                    ]
                )
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(OTAError.invalidResponse))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Debug: Print the full JSON response
                    print("[NRFCloud] Full JSON response:")
                    if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        print(jsonString)
                    } else {
                        print(json)
                    }
                    
                    // Parse the artifacts array to get URL and size
                    var url: String? = nil
                    var size: Int? = nil
                    
                    if let artifacts = json["artifacts"] as? [[String: Any]],
                       let firstArtifact = artifacts.first {
                        url = firstArtifact["url"] as? String
                        size = firstArtifact["file_size"] as? Int
                    }
                    
                    let updateInfo = UpdateInfo(
                        version: json["version"] as? String,
                        url: url,
                        size: size,
                        releaseNotes: json["notes"] as? String
                    )
                    
                    // Debug: Print parsed values
                    print("[NRFCloud] Parsed update info:")
                    print("  - Version: \(updateInfo.version ?? "nil")")
                    print("  - URL: \(updateInfo.url ?? "nil")")
                    print("  - Size: \(updateInfo.size ?? 0)")
                    print("  - Release Notes: \(updateInfo.releaseNotes ?? "nil")")
                    
                    // Status 200 means an update is available, even if some fields are missing
                    completion(.success(updateInfo))
                } else {
                    completion(.failure(OTAError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}