//
//  ObservabilityManager.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 8/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import Combine
internal import iOS_BLE_Library_Mock

// MARK: - ObservabilityManager

public final class ObservabilityManager {
    
    // MARK: Public Properties
    
    public typealias AsyncObservabilityDeviceStreamValue = (deviceUUID: UUID, event: ObservabilityDeviceEvent)
    public typealias AsyncObservabilityStream = AsyncThrowingStream<AsyncObservabilityDeviceStreamValue, Error>
    
    // MARK: Internal
    
    internal var ble = CentralManager()
    internal let network: Network
    
    internal var peripherals: [UUID: Peripheral]
    internal var devices: [UUID: ObservabilityDevice]
    internal var deviceStreams: [UUID: AsyncObservabilityStream.Continuation]
    
    internal var cancellables: Set<AnyCancellable>
    
    // MARK: init
    
    public init() {
        self.network = Network("chunks.memfault.com")
        self.peripherals = [UUID: Peripheral]()
        self.devices = [UUID: ObservabilityDevice]()
        self.deviceStreams = [UUID: AsyncObservabilityStream.Continuation]()
        self.cancellables = Set<AnyCancellable>()
        // Try to start inner CentralManager.
        _ = ble.centralManager.state
    }
}

// MARK: - Bluetooth

public extension ObservabilityManager {
    
    @discardableResult
    func connectToDevice(_ identifier: UUID) -> AsyncObservabilityStream {
        if devices[identifier] == nil {
            devices[identifier] = ObservabilityDevice(uuidString: identifier.uuidString)
        }
        
        let asyncObservabilityDeviceStream = AsyncObservabilityStream() { continuation in
            // To-Do: Is there a previous one?
            deviceStreams[identifier] = continuation
        }
        
        Task {
            await connectAndAuthenticate(from: identifier)
        }
        return asyncObservabilityDeviceStream
    }
    
    func disconnect(from identifier: UUID) {
        Task {
            guard let device = devices[identifier],
                  let peripheral = peripherals[identifier] else { return }
            do {
                if device.isStreaming {
                    guard let mdsService = peripheral.services?.first(where: { $0.uuid == CBUUID.MDS }),
                          let mdsDataExportCharacteristic = mdsService.characteristics?.first(where: { $0.uuid == CBUUID.MDSDataExportCharacteristic }) else {
                        throw ObservabilityManagerError.mdsDataExportCharacteristicNotFound
                    }
                    _ = try await peripheral.writeValueWithResponse(Data(repeating: 0, count: 1), for: mdsDataExportCharacteristic)
                        .firstValue
                    deviceStreams[identifier]?.yield((identifier, .streaming(false)))
                }
                
                if device.isNotifying {
                    guard let mdsService = peripheral.services?.first(where: { $0.uuid == CBUUID.MDS }),
                          let mdsDataExportService = mdsService.characteristics?.first(where: { $0.uuid == CBUUID.MDSDataExportCharacteristic }) else {
                        throw ObservabilityManagerError.mdsDataExportCharacteristicNotFound
                    }
                    
                    _ = try await peripheral.setNotifyValue(false, for: mdsDataExportService)
                        .firstValue
                    deviceStreams[identifier]?.yield((identifier, .notifications(false)))
                }
                
                _ = try await ble.cancelPeripheralConnection(peripheral.peripheral)
                    .firstValue
                deviceStreams[identifier]?.yield((identifier, .disconnected))
                deviceStreams[identifier]?.finish()
            } catch {
                deviceStreams[identifier]?.finish(throwing: error)
            }
        }
    }
}
    
// MARK: - Network

extension ObservabilityManager {
    
    func upload(_ chunk: ObservabilityChunk, with chunkAuth: ObservabilityAuth) async throws {
        _ = try await network.perform(HTTPRequest.post(chunk, with: chunkAuth))
            .firstValue
    }
}
