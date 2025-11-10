//
//  ObservabilityManager.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 8/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import Combine
import iOS_Common_Libraries
internal import iOS_BLE_Library_Mock

// MARK: - ObservabilityManager

public final class ObservabilityManager {
    
    // MARK: Private Constants
    
    /**
     How long (in seconds) should we wait before we trigger an automatic retry of sending pending chunks we've received from a device up to nRF Cloud / Memfault.
     */
    internal static let AutoUploadRetryDelay: TimeInterval = 30.0
    
    // MARK: Public Properties
    
    public typealias AsyncObservabilityDeviceStreamValue = (deviceUUID: UUID, event: ObservabilityDeviceEvent)
    public typealias AsyncObservabilityStream = AsyncThrowingStream<AsyncObservabilityDeviceStreamValue, Error>
    
    // MARK: Internal
    
    internal var ble = CentralManager()
    internal let network: Network
    
    internal var peripherals: [UUID: Peripheral]
    internal var devices: [UUID: ObservabilityDevice]
    internal var deviceContinuations: [UUID: AsyncObservabilityStream.Continuation]
    internal var deviceCancellables: [UUID: Set<AnyCancellable>]
    
    internal var state = ObservabilityState()
    internal var networkBusy = false
    internal var retryTimer: Timer?
    
    // MARK: init
    
    public init() {
        self.network = Network("chunks.memfault.com")
        self.peripherals = [UUID: Peripheral]()
        self.devices = [UUID: ObservabilityDevice]()
        self.deviceContinuations = [UUID: AsyncObservabilityStream.Continuation]()
        self.deviceCancellables = [UUID: Set<AnyCancellable>]()
        self.state.restoreFromDisk()
        log(#function)
    }
    
    // MARK: deinit
    
    deinit {
        log(#function)
    }
}

// MARK: - Bluetooth

public extension ObservabilityManager {
    
    // MARK: connect
    
    @discardableResult
    func connectToDevice(_ identifier: UUID) -> AsyncObservabilityStream {
        if devices[identifier] == nil {
            devices[identifier] = ObservabilityDevice(uuidString: identifier.uuidString)
            deviceCancellables[identifier] = Set<AnyCancellable>()
        }
        
        let asyncObservabilityDeviceStream = AsyncObservabilityStream() { continuation in
            // To-Do: Is there a previous one?
            deviceContinuations[identifier] = continuation
            continuation.onTermination = { @Sendable [weak self] termination in
                self?.log("Detected AsyncObservabilityStream termination.")
            }
        }
        
        Task {
            await connectAndAuthenticate(from: identifier)
        }
        return asyncObservabilityDeviceStream
    }
    
    // MARK: disconnect
    
    /**
     Fire-and-forget variant of ``disconnect(from:)-x5wz`` async API.
     
     If you'd like to disconnect from a device, or at least get ``ObservabilityManager`` to release its connection and confirm via the ``AsyncObservabilityStream`` from your previous call to ``connectToDevice(_:)`` you may do so from this API call.
     */
    func disconnect(from identifier: UUID) {
        Task {
            await disconnect(from: identifier)
        }
    }
    
    /**
     Disconnect from a device.
     
     This will close the returned ``AsyncObservabilityStream`` returned from a previous call to ``connectToDevice(_:)``. Additionally, since this is an `async` API call, you may await its return to update your UI.
     */
    func disconnect(from identifier: UUID) async {
        guard let device = devices[identifier],
              let peripheral = peripherals[identifier],
              let continuation = deviceContinuations[identifier] else { return }
        
        log(#function)
        defer {
            networkBusy = false
            retryTimer?.invalidate()
            retryTimer = nil
            deviceContinuations[identifier] = nil
            log("nil-ed out Device Continuation.")
        }
        
        do {
            if device.isStreaming {
                guard let mdsService = peripheral.services?.first(where: { $0.uuid == CBUUID.MDS }),
                      let mdsDataExportCharacteristic = mdsService.characteristics?.first(where: { $0.uuid == CBUUID.MDSDataExportCharacteristic }) else {
                    throw ObservabilityError.mdsDataExportCharacteristicNotFound
                }
                _ = try await peripheral.writeValueWithResponse(Data(repeating: 0, count: 1), for: mdsDataExportCharacteristic)
                    .firstValue
                continuation.yield((identifier, .streaming(false)))
            }
            
            if device.isNotifying {
                guard let mdsService = peripheral.services?.first(where: { $0.uuid == CBUUID.MDS }),
                      let mdsDataExportService = mdsService.characteristics?.first(where: { $0.uuid == CBUUID.MDSDataExportCharacteristic }) else {
                    throw ObservabilityError.mdsDataExportCharacteristicNotFound
                }
                
                _ = try await peripheral.setNotifyValue(false, for: mdsDataExportService)
                    .firstValue
                continuation.yield((identifier, .notifications(false)))
            }
            
            _ = try await ble.cancelPeripheralConnection(peripheral.peripheral)
                .firstValue
            continuation.yield((identifier, .disconnected))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
            logError("Error when attempting to disconnect: \(error.localizedDescription)")
        }
    }
    
    // MARK: continue / retry
    
    func continuePendingUploads(for identifier: UUID) throws {
        guard peripherals[identifier] != nil else {
            throw ObservabilityError.peripheralNotFound
        }
        
        guard deviceContinuations[identifier] != nil else {
            throw ObservabilityError.peripheralNotConnected
        }
        
        guard let auth = devices[identifier]?.auth else {
            throw ObservabilityError.missingAuthData
        }
        resumeUploadsIfNotBusy(for: identifier, with: auth)
    }
}
