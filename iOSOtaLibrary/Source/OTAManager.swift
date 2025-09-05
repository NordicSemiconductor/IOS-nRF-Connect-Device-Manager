//
//  iOSOtaLibrary.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 2/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import CoreBluetooth
internal import iOS_BLE_Library_Mock

// MARK: - OTAManager

public final class OTAManager {
    
    // MARK: Private Properties
    
    internal var ble = CentralManager()
    internal let peripheralUUID: UUID
    internal var peripheral: Peripheral?
    private let network: Network
    
    // MARK: init
    
    public init(_ targetPeripheralUUID: UUID) {
        self.ble = CentralManager()
        self.peripheralUUID = targetPeripheralUUID
        // Try to start inner CentralManager.
        _ = ble.centralManager.state
        self.network = Network("api.memfault.com")
    }
}

// MARK: - API

public extension OTAManager {
    
    // MARK: Release Info
    
    func getLatestReleaseInfo(deviceInfo: DeviceInfoToken, projectKey: ProjectKey, callback: @escaping (Result<LatestReleaseInfo, OTAManagerError>) -> ()) {
        Task { @MainActor in
            do {
                let releaseInfo = try await getLatestReleaseInfo(deviceInfo: deviceInfo, projectKey: projectKey)
                callback(.success(releaseInfo))
            } catch {
                guard let otaError = error as? OTAManagerError else {
                    callback(.failure(.incompleteDeviceInfo))
                    return
                }
                callback(.failure(otaError))
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    func getLatestReleaseInfo(deviceInfo: DeviceInfoToken, projectKey: ProjectKey) async throws -> LatestReleaseInfo {
        do {
            guard let releaseInfoRequest = HTTPRequest.getLatestReleaseInfo(token: deviceInfo, key: projectKey) else {
                throw OTAManagerError.incompleteDeviceInfo
            }
            
            let responseData = try await network.perform(releaseInfoRequest)
                .firstValue
            
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
            guard let releaseInfo = try? decoder.decode(LatestReleaseInfo.self, from: responseData) else {
                throw OTAManagerError.unableToParseResponse
            }
            return releaseInfo
        } catch {
            throw error
        }
    }
}

// MARK: - Private

extension OTAManager {
    
    func awaitBleStart() async throws {
        switch ble.centralManager.state {
        case .poweredOff, .unauthorized, .unsupported:
            throw OTAManagerError.bleUnavailable
        default:
            break
        }
        
        _ = try await ble.stateChannel
            .filter {
                switch $0 {
                case .unauthorized, .unsupported, .poweredOff:
                    return false
                case .poweredOn:
                    return true
                default:
                    return false
                }
            }
            .firstValue
    }
}

// MARK: - OTAManagerError

public enum OTAManagerError: LocalizedError {
    case bleUnavailable
    case peripheralNotFound
    case serviceNotFound
    case incompleteDeviceInfo
    case mdsKeyDecodeError
    case unableToParseResponse
}
