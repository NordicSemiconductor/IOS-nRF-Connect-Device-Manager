//
//  iOSOtaLibrary.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 2/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import CoreBluetooth
import CryptoKit
import iOS_Common_Libraries
import iOSMcuManagerLibrary

// MARK: - OTAManager

public final class OTAManager {
    
    // MARK: Private Properties
    
    private let network: Network
    private var memfaultManager: MemfaultManager?
    
    // MARK: Properties
    
    public weak var logDelegate: (any McuMgrLogDelegate)?
    
    // MARK: init
    
    public init() {
        network = Network("api.memfault.com")
    }
    
    // MARK: deinit
    
    deinit {
        print(#function)
        logDelegate = nil
    }
}

// MARK: - API

public extension OTAManager {
    
    // MARK: getDeviceInfoToken
    
    func getDeviceInfoToken(via transport: any McuMgrTransport) async throws -> DeviceInfoToken {
        if memfaultManager != nil {
            memfaultManager = nil
        }
        
        do {
            let manager = MemfaultManager(transport: transport)
            memfaultManager = manager
            memfaultManager?.logDelegate = logDelegate
            return try await manager.readDeviceInfo()
        } catch {
            throw error
        }
    }
    
    // MARK: getProjectKey
    
    func getProjectKey(via transport: any McuMgrTransport) async throws -> ProjectKey {
        if memfaultManager != nil {
            memfaultManager = nil
        }
        
        do {
            let manager = MemfaultManager(transport: transport)
            memfaultManager = manager
            memfaultManager?.logDelegate = logDelegate
            return try await manager.readProjectKey()
        } catch {
            throw error
        }
    }
    
    // MARK: Release Info
    
    /**
     Callback (i.e. pre-concurrency) variant of ``OTAManager/getLatestReleaseInfo(deviceInfo:projectKey:)`` API.
     */
    func getLatestReleaseInfo(deviceInfo: DeviceInfoToken, projectKey: ProjectKey, callback: @escaping (Result<LatestReleaseInfo, OTAManagerError>) -> ()) {
        Task { @MainActor in
            do {
                let releaseInfo = try await getLatestReleaseInfo(deviceInfo: deviceInfo,
                                                                 projectKey: projectKey)
                callback(.success(releaseInfo))
            } catch {
                guard let otaError = error as? OTAManagerError else {
                    callback(.failure(.unknownError(error)))
                    return
                }
                callback(.failure(otaError))
            }
        }
    }
    
    func getLatestReleaseInfo(deviceInfo: DeviceInfoToken, projectKey: ProjectKey) async throws -> LatestReleaseInfo {
        do {
            guard let releaseInfoRequest = HTTPRequest.getLatestReleaseInfo(token: deviceInfo, key: projectKey) else {
                throw OTAManagerError.incompleteDeviceInfo
            }
            
            let response = try await network.perform(releaseInfoRequest)
                .firstValue
            
            // Status Code 204 from the Server means "No Content", or "Up to Date"
            guard response.code != 204 else {
                throw OTAManagerError.deviceIsUpToDate
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // The .iso8601 decoding strategy does not support fractional seconds.
            // decoder.dateDecodingStrategy = .iso8601
            
            // Instead, use ISO8601DateFormatter.
            decoder.dateDecodingStrategy = .custom { decoder in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions.insert(.withFractionalSeconds)
                
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                return formatter.date(from: value) ?? Date.distantPast
            }
            guard let releaseInfo = try? decoder.decode(LatestReleaseInfo.self, from: response.data) else {
                throw OTAManagerError.unableToParseResponse
            }
            return releaseInfo
        } catch let networkError as URLError {
            if networkError.code == .userAuthenticationRequired {
                throw OTAManagerError.invalidProjectKey(deviceInfo)
            } else {
                throw OTAManagerError.networkError
            }
        } catch {
            throw error
        }
    }
    
    // MARK: Download Artifact
    
    /**
     Callback (i.e. pre-concurrency) variant of ``OTAManager/download(artifact:)`` API.
     */
    func download(artifact: ReleaseArtifact, callback: @escaping (Result<URL, OTAManagerError>) -> ()) {
        Task { @MainActor in
            do {
                let temporaryDownloadedFileURL = try await download(artifact: artifact)
                callback(.success(temporaryDownloadedFileURL))
            } catch {
                guard let otaError = error as? OTAManagerError else {
                    callback(.failure(.unableToParseResponse))
                    return
                }
                callback(.failure(otaError))
            }
        }
    }
    
    /**
     - returns: A local temporary URL to the downloaded artifact on success. Keep in mind this is temporary local storage so, move the file to a more secure location if you intend to keep it.
     */
    func download(artifact: ReleaseArtifact) async throws -> URL {
        guard let parsedURL = artifact.releaseURL() else {
            throw OTAManagerError.invalidArtifactURL
        }
        
        let downloadRequest = HTTPRequest(url: parsedURL)
        let response = try await network.perform(downloadRequest)
            .firstValue
        
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let localArtifactURL = tempDirectoryURL.appendingPathComponent(artifact.filename)
        do {
            // Write file to temporary URL
            try response.data.write(to: localArtifactURL)
            
            // Check SHA256 Hash matches.
            let downloadedFileHash = try sha256Hash(of: localArtifactURL)
            let downloadedFileHashString = downloadedFileHash.map {
                String(format: "%02hhx", $0)
            }
            .joined()
            guard downloadedFileHashString.localizedCaseInsensitiveContains(artifact.sha256) else {
                throw OTAManagerError.sha256HashMismatch
            }
            
            return localArtifactURL
        } catch {
            throw error
        }
    }
}

// MARK: - Private

extension OTAManager {
    
    func sha256Hash(of fileURL: URL) throws -> SHA256.Digest {
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return SHA256.hash(data: fileData)
    }
}

// MARK: - OTAManagerError

public enum OTAManagerError: LocalizedError {
    case incompleteDeviceInfo
    case mdsKeyDecodeError
    case unableToParseResponse
    case networkError
    case invalidProjectKey(_ deviceInfo: DeviceInfoToken)
    case deviceIsUpToDate
    case invalidArtifactURL
    case sha256HashMismatch
    
    case unknownError(_ error: Error)
}
