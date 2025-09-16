//
//  ObservabilityManager+Internal.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 8/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import CoreBluetooth
internal import iOS_BLE_Library_Mock
import Combine

// MARK: - Internal

extension ObservabilityManager {
    
    // MARK: connectAndAuthenticate
    
    func connectAndAuthenticate(from identifier: UUID) async {
        do {
            try await awaitBleStart()
            
            let cbPeripheral = ble.retrievePeripherals(withIdentifiers: [identifier])
                .first
            
            guard let cbPeripheral else {
                throw ObservabilityManagerError.peripheralNotFound
            }
            
            let connectionPublisher = ble.connect(cbPeripheral)
            // Await connection or error is thrown.
            _ = try await connectionPublisher
                .firstValue
            
            devices[identifier]?.isConnected = true
            deviceStreams[identifier]?.yield((identifier, .connected))
            let peripheral = Peripheral(peripheral: cbPeripheral, delegate: ReactivePeripheralDelegate())
            peripherals[identifier] = peripheral
            
            listenForDisconnectionEvents(from: identifier, publisher: connectionPublisher)
            
            let discoveredServices = try await peripheral.discoverServices(serviceUUIDs: nil)
                .timeout(5, scheduler: DispatchQueue.main)
                .firstValue
            
            guard let mdsService = discoveredServices.first(where: { $0.uuid == CBUUID.MDS }) else {
                throw ObservabilityManagerError.mdsServiceNotFound
            }
            
            let mdsCharacteristics = try await peripheral.discoverCharacteristics([], for: mdsService)
                .firstValue
            guard let mdsData = mdsCharacteristics.first(where: { $0.uuid == CBUUID.MDSDataExportCharacteristic }) else {
                throw ObservabilityManagerError.mdsDataExportCharacteristicNotFound
            }
            
            if #available(iOS 15.0, *) {
                try listenForNewChunks(from: peripheral, dataExportCharacteristic: mdsData)
            } else {
                // TODO: Fallback on earlier versions
                throw ObservabilityManagerError.iOSVersionTooLow("iOS 15 / macCatalyst 15 / macOS 12 onwards are required.")
            }
            
            guard let mdsDataURI = mdsCharacteristics.first(where: { $0.uuid == CBUUID.MDSDataURICharacteristic }),
                  let uriData = try await peripheral.readValue(for: mdsDataURI).firstValue,
                  let uriString = String(data: uriData, encoding: .utf8),
                  let uriURL = URL(string: uriString) else {
                throw ObservabilityManagerError.unableToReadDeviceURI
            }
            
            guard let mdsAuth = mdsCharacteristics.first(where: { $0.uuid == CBUUID.MDSAuthCharacteristic }),
                  let authData = try await peripheral.readValue(for: mdsAuth).firstValue,
                  let authString = String(data: authData, encoding: .utf8)?.split(separator: ":") else {
                throw ObservabilityManagerError.unableToReadAuthData
            }
            
            let auth = ObservabilityAuth(url: uriURL, authKey: String(authString[0]),
                                          authValue: String(authString[1]))
            devices[identifier]?.auth = auth
            deviceStreams[identifier]?.yield((identifier, .authenticated(auth)))
            
            let setNotifyResult = try await peripheral.setNotifyValue(true, for: mdsData)
                .firstValue
            devices[identifier]?.isNotifying = setNotifyResult
            deviceStreams[identifier]?.yield((identifier, .notifications(setNotifyResult)))

            // Write 0x1 to MDS Device to make it aware we're ready to receive chunks.
            try await peripheral.writeValueWithResponse(Data(repeating: 1, count: 1), for: mdsData)
                .firstValue
            
            devices[identifier]?.isStreaming = true
            deviceStreams[identifier]?.yield((identifier, .streaming(true)))
        } catch {
            deviceStreams[identifier]?.yield(with: .failure(error))
            // Is disconnect here necessary? It was not in Memfault-lib.
//            disconnect(from: identifier)
        }
    }
    
    func listenForDisconnectionEvents(from identifier: UUID, publisher: AnyPublisher<iOS_BLE_Library_Mock.CBPeripheral, Error>) {
        publisher
            .sink { [weak self] completion in
                guard let self else { return }
                switch completion {
                case .failure(let error):
                    deviceStreams[identifier]?.yield((identifier, .notifications(false)))
                    deviceStreams[identifier]?.yield((identifier, .streaming(false)))
                    deviceStreams[identifier]?.finish(throwing: error)
                case .finished:
                    deviceStreams[identifier]?.finish()
                }
            } receiveValue: { _ in
                
            }
            .store(in: &cancellables)
    }
}

// MARK: - listenForNewChunks

@available(iOS 15.0, macCatalyst 15.0, macOS 12.0, *)
extension ObservabilityManager {
    
    func listenForNewChunks(from peripheral: Peripheral, dataExportCharacteristic: iOS_BLE_Library_Mock.CBCharacteristic) throws {
        
        Task {
            let identifier = peripheral.peripheral.identifier
            var auth: ObservabilityAuth!
            do {
                for try await data in peripheral
                    .listenValues(for: dataExportCharacteristic)
                    .buffer(size: 100, prefetch: .byRequest, whenFull: .customError({
                        ObservabilityManagerError.droppedChunkDueToFullBuffer
                    })).values {
                    
                    let chunk = ObservabilityChunk(data)
                    received(chunk, from: identifier)
                    
                    if auth == nil {
                        auth = devices[identifier]?.auth
                    }
                    
                    guard let auth else {
                        throw ObservabilityManagerError.missingAuthData
                    }
                    
                    try await upload(chunk, with: auth, from: identifier)
                }
            } catch {
                deviceStreams[identifier]?.yield(with: .failure(error))
                disconnect(from: identifier)
            }
        }
    }
}

// MARK: - Private

extension ObservabilityManager {
    
    // MARK: upload
    
    func upload(_ chunk: ObservabilityChunk, with auth: ObservabilityAuth, from identifier: UUID) async throws {
        guard let i = devices[identifier]?.chunks.firstIndex(where: {
            $0.sequenceNumber == chunk.sequenceNumber && $0.data == chunk.data
        }) else { return }

        do {
            devices[identifier]?.chunks[i].status = .uploading
            deviceStreams[identifier]?.yield((identifier, .updatedChunk(chunk, status: .uploading)))
            try await upload(chunk, with: auth)
            devices[identifier]?.chunks[i].status = .success
            deviceStreams[identifier]?.yield((identifier, .updatedChunk(chunk, status: .success)))
        } catch {
            devices[identifier]?.chunks[i].status = .errorUploading
            deviceStreams[identifier]?.yield((identifier, .updatedChunk(chunk, status: .errorUploading)))
            disconnect(from: identifier)
        }
    }
    
    // MARK: received
    
    func received(_ chunk: ObservabilityChunk, from identifier: UUID) {
        devices[identifier]?.chunks.append(chunk)
        deviceStreams[identifier]?.yield((identifier, .updatedChunk(chunk, status: .receivedAndPendingUpload)))
    }
    
    // MARK: awaitBleStart
    
    func awaitBleStart() async throws {
        switch ble.centralManager.state {
        case .poweredOff, .unauthorized, .unsupported:
            throw ObservabilityManagerError.bleUnavailable
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
