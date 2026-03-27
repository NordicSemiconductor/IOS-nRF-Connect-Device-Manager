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
    
    // MARK: Properties
    
    private(set) var mcuMgrParams: (bufferCount: Int, bufferSize: Int)?
    private(set) var appInfoOutput: String?
    private(set) var bootloader: BootloaderInfoResponse.Bootloader?
    private(set) var bootloaderMode: BootloaderInfoResponse.Mode?
    private(set) var bootloaderSlot: UInt64?
    private(set) var otaStatus: OTAStatus?
    
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
    
    // MARK: requestStatus
    
    func requestStatus() async {
        async let mcuMgrParams = defaultManager.params()
        async let appInfo = defaultManager.applicationInfo(format: [.kernelName, .kernelVersion])
        async let bootloaderInfo = defaultManager.bootloaderInfo()
        
        self.mcuMgrParams = try? await mcuMgrParams
        self.appInfoOutput = try? await appInfo
        self.bootloader = try? await bootloaderInfo.bootloader
        self.bootloaderMode = try? await bootloaderInfo.mode
        self.bootloaderSlot = try? await bootloaderInfo.slot
    }
    
    // MARK: requestOTAStatus
    
    func requestOTAStatus(for peripheralUUID: UUID) async {
        let deviceInfoManager = DeviceInfoManager(peripheralUUID)
        do {
            let tokens = try await requestTokensViaMemfaultManager()
            otaStatus = .supported(tokens.0, tokens.1)
        } catch {
            // Disregard error. Try again through Device Information.
            var deviceInfo: DeviceInfoToken!
            do {
                deviceInfo = try await deviceInfoManager.getDeviceInfoToken()
                let projectKey = try await deviceInfoManager.getProjectKey()
                otaStatus = .supported(deviceInfo, projectKey)
            } catch let managerError as DeviceInfoManagerError {
                if deviceInfo != nil {
                    otaStatus = .missingProjectKey(deviceInfo, managerError)
                } else {
                    otaStatus = .unsupported(managerError)
                }
            } catch let error {
                otaStatus = .unsupported(error)
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

// MARK: - Delegate

extension DeviceStatusManager {
    
    protocol Delegate: AnyObject {
        
        func connectionStateDidChange(_ state: PeripheralState)
        func bootloaderNameReceived(_ name: String)
        func bootloaderModeReceived(_ mode: BootloaderInfoResponse.Mode)
        func bootloaderSlotReceived(_ slot: UInt64)
        func appInfoReceived(_ output: String)
        func mcuMgrParamsReceived(buffers: Int, size: Int)
        func otaStatusChanged(_ status: OTAStatus)
        func observabilityStatusChanged(_ status: ObservabilityStatus, pendingCount: Int, pendingBytes: Int, uploadedCount: Int, uploadedBytes: Int)
    }
}
