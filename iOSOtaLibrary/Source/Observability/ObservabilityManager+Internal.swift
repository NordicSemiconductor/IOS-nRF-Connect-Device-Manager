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
            log(#function)
            
            guard let cbPeripheral = ble.retrievePeripherals(withIdentifiers: [identifier])
                .first else {
                throw ObservabilityError.peripheralNotFound
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
                throw ObservabilityError.mdsServiceNotFound
            }
            
            let mdsCharacteristics = try await peripheral.discoverCharacteristics([], for: mdsService)
                .firstValue
            guard let mdsData = mdsCharacteristics.first(where: { $0.uuid == CBUUID.MDSDataExportCharacteristic }) else {
                throw ObservabilityError.mdsDataExportCharacteristicNotFound
            }
            
            reportPendingChunks(from: peripheral)
            try listenForNewChunks(from: peripheral, dataExportCharacteristic: mdsData)
            
            guard let mdsDataURI = mdsCharacteristics.first(where: { $0.uuid == CBUUID.MDSDataURICharacteristic }),
                  let uriData = try await peripheral.readValue(for: mdsDataURI).firstValue,
                  let uriString = String(data: uriData, encoding: .utf8),
                  let uriURL = URL(string: uriString) else {
                throw ObservabilityError.unableToReadDeviceURI
            }
            
            guard let mdsAuth = mdsCharacteristics.first(where: { $0.uuid == CBUUID.MDSAuthCharacteristic }),
                  let authData = try await peripheral.readValue(for: mdsAuth).firstValue,
                  let authString = String(data: authData, encoding: .utf8)?.split(separator: ":") else {
                throw ObservabilityError.unableToReadAuthData
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
            
            guard state.pendingChunks(for: identifier).hasItems else { return }
            resumeUploadsIfNotBusy(for: identifier, with: auth)
        } catch CBATTError.insufficientEncryption {
            deviceContinuations[identifier]?.yield(with: .failure(ObservabilityError.pairingError))
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
            throw ObservabilityError.peripheralNotFound
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
                //                log("Device disconnected.")
                //                deviceContinuations[identifier] = nil
            } receiveValue: { _ in
                // No-op.
            }
            .store(in: &deviceCancellables[identifier]!)
    }

    // MARK: reportPendingChunks
    
    func reportPendingChunks(from peripheral: Peripheral) {
        let identifier = peripheral.peripheral.identifier
        let pendingChunks = state.pendingChunks(for: identifier)
        for chunk in pendingChunks {
            let pendingChunk = state.update(chunk, from: identifier, to: .pendingUpload)
            deviceContinuations[identifier]?.yield((identifier, .updatedChunk(pendingChunk)))
        }
    }
    
    // MARK: listenForNewChunks
    
    func listenForNewChunks(from peripheral: Peripheral, dataExportCharacteristic: iOS_BLE_Library_Mock.CBCharacteristic) throws {
        let identifier = peripheral.peripheral.identifier
        guard deviceCancellables[identifier] != nil else {
            throw ObservabilityError.peripheralNotFound
        }
        
        peripheral
            .listenValues(for: dataExportCharacteristic)
            .map { [weak self] data in
                ObservabilityChunk(data)
            }
            .tryMap { [weak self] chunk -> (ObservabilityAuth, ObservabilityChunk) in
                guard let auth = self?.devices[identifier]?.auth else {
                    throw ObservabilityError.missingAuthData
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
            } receiveValue: { [weak self] auth, incomingChunk in
                guard let self else { return }
                received(incomingChunk, from: identifier)
                resumeUploadsIfNotBusy(for: identifier, with: auth)
            }
            .store(in: &deviceCancellables[identifier]!)
    }
    
    // MARK: resumeUploadsIfNotBusy
    
    func resumeUploadsIfNotBusy(for identifier: UUID, with auth: ObservabilityAuth) {
        guard !networkBusy, let nextChunk = state.nextChunk(for: identifier) else { return }
        log("Sending for Upload Chunk Seq. Number \(nextChunk.sequenceNumber)")
        networkBusy = true
        upload(nextChunk, with: auth, from: identifier)
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
                    self?.networkBusy = false
                case .failure(let error):
                    guard let self else { return }
                    let updatedChunk = state.update(uploadingChunk, from: identifier, to: .uploadError)
                    deviceContinuations[identifier]?.yield((identifier, .updatedChunk(updatedChunk)))
                    networkBusy = false
                    deviceContinuations[identifier]?.yield((identifier, .unableToUpload))
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
