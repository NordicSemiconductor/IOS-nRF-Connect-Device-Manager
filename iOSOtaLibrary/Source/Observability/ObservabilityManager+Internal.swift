//
//  ObservabilityManager+Internal.swift
//  iOSOtaLibrary
//
//  Created by Dinesh Harjani on 8/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import CoreBluetooth
import Combine
import iOS_Common_Libraries
internal import iOS_BLE_Library_Mock

// MARK: - Internal

internal extension ObservabilityManager {
    
    // MARK: connectAndAuthenticate
    
    func connectAndAuthenticate(from identifier: UUID) async {
        do {
            try await ble.isPoweredOn()
            
            guard let cbPeripheral = ble.retrievePeripherals(withIdentifiers: [identifier])
                .first else {
                throw ObservabilityManagerError.peripheralNotFound
            }
            
            let connectionPublisher = ble.connect(cbPeripheral)
            // Await connection or error is thrown.
            _ = try await connectionPublisher
                .firstValue
            
            devices[identifier]?.isConnected = true
            deviceContinuations[identifier]?.yield((identifier, .connected))
            let peripheral = Peripheral(peripheral: cbPeripheral)
            peripherals[identifier] = peripheral
            
            try listenForDisconnectionEvents(from: identifier, publisher: connectionPublisher)
            
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
            
            reportPendingChunks(from: peripheral)
            try listenForNewChunks(from: peripheral, dataExportCharacteristic: mdsData)
            
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
            deviceContinuations[identifier]?.yield((identifier, .authenticated(auth)))
            
            let setNotifyResult = try await peripheral.setNotifyValue(true, for: mdsData)
                .firstValue
            devices[identifier]?.isNotifying = setNotifyResult
            deviceContinuations[identifier]?.yield((identifier, .notifications(setNotifyResult)))
            
            // Write 0x1 to MDS Device to make it aware we're ready to receive chunks.
            try await peripheral.writeValueWithResponse(Data(repeating: 1, count: 1), for: mdsData)
                .firstValue
            
            devices[identifier]?.isStreaming = true
            deviceContinuations[identifier]?.yield((identifier, .streaming(true)))
        } catch CBATTError.insufficientEncryption {
            deviceContinuations[identifier]?.yield(with: .failure(ObservabilityManagerError.pairingError))
            deviceCancellables[identifier]?.removeAll()
        } catch {
            deviceContinuations[identifier]?.yield(with: .failure(error))
            deviceCancellables[identifier]?.removeAll()
            // Is disconnect here necessary? It was not in Memfault-lib.
//            disconnect(from: identifier)
        }
    }
    
    // MARK: listenForDisconnectionEvents
    
    func listenForDisconnectionEvents(from identifier: UUID, publisher: AnyPublisher<iOS_BLE_Library_Mock.CBPeripheral, Error>) throws {
        guard deviceCancellables[identifier] != nil else {
            throw ObservabilityManagerError.peripheralNotFound
        }
        
        publisher
            .sink { [weak self] completion in
                guard let self else { return }
                switch completion {
                case .failure(let error):
                    deviceContinuations[identifier]?.yield((identifier, .notifications(false)))
                    deviceContinuations[identifier]?.yield((identifier, .streaming(false)))
                    deviceContinuations[identifier]?.finish(throwing: error)
                    deviceCancellables[identifier]?.removeAll()
                case .finished:
                    deviceContinuations[identifier]?.finish()
                    deviceCancellables[identifier]?.removeAll()
                }
            } receiveValue: { _ in
                // No-op.
            }
            .store(in: &deviceCancellables[identifier]!)
    }

    // MARK: reportPendingChunks
    
    func reportPendingChunks(from peripheral: Peripheral) {
        let identifier = peripheral.peripheral.identifier
        for chunk in state.pendingUploads[identifier] ?? [] {
            let pendingChunk = state.update(chunk, from: identifier, to: .pendingUpload)
            deviceContinuations[identifier]?.yield((identifier, .updatedChunk(pendingChunk)))
        }
    }
    
    // MARK: listenForNewChunks
    
    func listenForNewChunks(from peripheral: Peripheral, dataExportCharacteristic: iOS_BLE_Library_Mock.CBCharacteristic) throws {
        let identifier = peripheral.peripheral.identifier
        guard deviceCancellables[identifier] != nil else {
            throw ObservabilityManagerError.peripheralNotFound
        }
        
        peripheral
            .listenValues(for: dataExportCharacteristic)
            .map { [weak self] data in
                let chunk = ObservabilityChunk(data)
                self?.received(chunk, from: identifier)
                return chunk
            }
            .tryMap { [weak self] chunk -> (ObservabilityAuth, ObservabilityChunk) in
                guard let auth = self?.devices[identifier]?.auth else {
                    throw ObservabilityManagerError.missingAuthData
                }
                return (auth, chunk)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] completion in
                switch completion {
                case .finished:
                    self?.log("finished")
                case .failure(let error):
                    self?.logError(error.localizedDescription)
                    self?.deviceContinuations[identifier]?
                        .yield(with: .failure(error))
                    self?.disconnect(from: identifier)
                }
            } receiveValue: { [weak self] auth, chunk in
                guard let self, !networkBusy else { return }
                log("Sending for Upload Chunk Seq. Number \(chunk.sequenceNumber)")
                networkBusy = true
                upload(chunk, with: auth, from: identifier)
            }
            .store(in: &deviceCancellables[identifier]!)
    }
}

// MARK: - Private

extension ObservabilityManager {
    
    // MARK: received
    
    func received(_ chunk: ObservabilityChunk, from identifier: UUID) {
        log("Received Chunk Seq. Number \(chunk.sequenceNumber)")
        state.add([chunk], for: identifier)
        deviceContinuations[identifier]?.yield((identifier, .updatedChunk(chunk)))
    }
    
    // MARK: upload
    
    func upload(_ chunk: ObservabilityChunk, with auth: ObservabilityAuth, from identifier: UUID) {
        guard deviceCancellables[identifier] != nil else { return }
        log("Uploading Chunk Seq. Number \(chunk.sequenceNumber)")
        
        let uploadingChunk = state.update(chunk, from: identifier, to: .uploading)
        deviceContinuations[identifier]?.yield((identifier, .updatedChunk(uploadingChunk)))
        network.perform(HTTPRequest.post(uploadingChunk, with: auth))
            .receive(on: RunLoop.main)
            .sink { [weak self] completion in
                switch completion {
                case .finished:
                    self?.log("finished!")
                case .failure(let error):
                    guard let self else { return }
                    let updatedChunk = state.update(uploadingChunk, from: identifier, to: .errorUploading)
                    deviceContinuations[identifier]?.yield((identifier, .updatedChunk(updatedChunk)))
                    disconnect(from: identifier)
                }
            } receiveValue: { [weak self] resultData in
                guard let self else { return }
                log("Uploaded Chunk Seq. Number \(uploadingChunk.sequenceNumber)")
                let successfulChunk = state.update(uploadingChunk, from: identifier, to: .success)
                deviceContinuations[identifier]?.yield((identifier, .updatedChunk(successfulChunk)))
                state.clear(successfulChunk, from: identifier)
                guard let nextUpload = state.nextChunk(for: identifier) else {
                    networkBusy = false
                    return
                }
                upload(nextUpload, with: auth, from: identifier)
            }
            .store(in: &deviceCancellables[identifier]!)
    }
}
