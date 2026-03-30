//
//  DeviceStatusState.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 26/3/26.
//  Copyright © 2026 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import SwiftUI
import iOSMcuManagerLibrary
import iOSOtaLibrary

// MARK: - DeviceStatusManager

final class DeviceStatusManager {
    
    // MARK: Private Properties
    
    private weak var transport: McuMgrTransport?
    private weak var logDelegate: (any McuMgrLogDelegate)?
    private let defaultManager: DefaultManager
    
    // MARK: init
    
    init(_ transport: McuMgrTransport, logDelegate: (any McuMgrLogDelegate)?) {
        self.transport = transport
        self.logDelegate = logDelegate
        self.defaultManager = DefaultManager(transport: transport)
        defaultManager.logDelegate = logDelegate
    }
}

// MARK: API

extension DeviceStatusManager {
    
    // MARK: requestStatusInfo
    
    func requestStatusInfo() async -> DeviceStatusInfo {
        async let mcuMgrParametersResponse = defaultManager.params()
        async let appInfoResponse = defaultManager.applicationInfo(format: [.kernelName, .kernelVersion])
        async let bootloaderInfo = defaultManager.bootloaderInfo()
        
        var info = DeviceStatusInfo()
        if let mcuMgrParams = try? await mcuMgrParametersResponse {
            info.bufferSize = mcuMgrParams.bufferSize
            info.bufferCount = mcuMgrParams.bufferCount
        }
        info.appInfoOutput = (try? await appInfoResponse)?.response
        info.bootloader = try? await bootloaderInfo.bootloader
        info.bootloaderMode = try? await bootloaderInfo.mode
        info.bootloaderSlot = try? await bootloaderInfo.slot
        return info
    }
    
    // MARK: requestOTAStatus
    
    func requestOTAStatus(for peripheralUUID: UUID) async -> OTAStatus {
        let deviceInfoManager = DeviceInfoManager(peripheralUUID)
        do {
            let tokens = try await requestTokensViaMemfaultManager()
            return .supported(tokens.0, tokens.1)
        } catch {
            // Disregard error. Try again through Device Information.
            var deviceInfo: DeviceInfoToken!
            do {
                deviceInfo = try await deviceInfoManager.getDeviceInfoToken()
                let projectKey = try await deviceInfoManager.getProjectKey()
                return .supported(deviceInfo, projectKey)
            } catch let managerError as DeviceInfoManagerError {
                if deviceInfo != nil {
                    return .missingProjectKey(deviceInfo, managerError)
                } else {
                    return .unsupported(managerError)
                }
            } catch let error {
                return .unsupported(error)
            }
        }
    }
}

// MARK: - Private

fileprivate extension DeviceStatusManager {
    
    // MARK: requestTokensViaMemfaultManager
    
    func requestTokensViaMemfaultManager() async throws -> (DeviceInfoToken, ProjectKey) {
        guard let transport else {
            throw ObservabilityError.mdsServiceNotFound
        }
        let otaManager = OTAManager()
        otaManager.logDelegate = logDelegate
        let deviceInfo = try await otaManager.getDeviceInfoToken(via: transport)
        let projectKey = try await otaManager.getProjectKey(via: transport)
        return (deviceInfo, projectKey)
    }
}

// MARK: - DeviceStatusInfo

struct DeviceStatusInfo {
    
    var bufferCount: UInt64?
    var bufferSize: UInt64?
    var appInfoOutput: String?
    var bootloader: BootloaderInfoResponse.Bootloader?
    var bootloaderMode: BootloaderInfoResponse.Mode?
    var bootloaderSlot: UInt64?
}

// MARK: - Delegate

extension DeviceStatusManager {
    
    protocol Delegate: AnyObject {
        
        func statusInfoDidChange(_ info: DeviceStatusInfo)
        func connectionStateDidChange(_ state: PeripheralState)
        func otaStatusChanged(_ status: OTAStatus)
        func observabilityStatusChanged(_ statusInfo: ObservabilityStatusInfo)
    }
}
