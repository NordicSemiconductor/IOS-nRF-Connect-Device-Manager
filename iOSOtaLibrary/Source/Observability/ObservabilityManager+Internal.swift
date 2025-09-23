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
            let peripheral = Peripheral(peripheral: cbPeripheral, delegate: ReactivePeripheralDelegate())
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
        } catch {
            deviceContinuations[identifier]?.yield(with: .failure(error))
            deviceCancellables[identifier]?.removeAll()
            // Is disconnect here necessary? It was not in Memfault-lib.
//            disconnect(from: identifier)
        }
    }
    
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
            .sink { [weak self] completion in
                switch completion {
                case .finished:
                    print("finished")
                case .failure(let error):
                    print(error.localizedDescription)
                    self?.deviceContinuations[identifier]?.yield(with: .failure(error))
                    self?.disconnect(from: identifier)
                }
            } receiveValue: { [weak self] auth, chunk in
                self?.upload(chunk, with: auth, from: identifier)
            }
            .store(in: &deviceCancellables[identifier]!)
    }
}

// MARK: - Private

extension ObservabilityManager {
    
    // MARK: upload
    
    func upload(_ chunk: ObservabilityChunk, with auth: ObservabilityAuth, from identifier: UUID) {
        guard let i = devices[identifier]?.chunks.firstIndex(where: {
            $0.sequenceNumber == chunk.sequenceNumber && $0.data == chunk.data
        }) else { return }

        guard deviceCancellables[identifier] != nil else { return }
        devices[identifier]?.chunks[i].status = .uploading
        deviceContinuations[identifier]?.yield((identifier, .updatedChunk(chunk, status: .uploading)))
        
        network.perform(HTTPRequest.post(chunk, with: auth))
            .sink { [weak self] completion in
                switch completion {
                case .finished:
                    print("finished!")
                case .failure(let error):
                    self?.devices[identifier]?.chunks[i].status = .errorUploading
                    self?.deviceContinuations[identifier]?.yield((identifier, .updatedChunk(chunk, status: .errorUploading)))
                    self?.disconnect(from: identifier)
                }
            } receiveValue: { [weak self] resultData in
                self?.devices[identifier]?.chunks[i].status = .success
                self?.deviceContinuations[identifier]?.yield((identifier, .updatedChunk(chunk, status: .success)))
            }
            .store(in: &deviceCancellables[identifier]!)
    }
    
    // MARK: received
    
    func received(_ chunk: ObservabilityChunk, from identifier: UUID) {
        devices[identifier]?.chunks.append(chunk)
        deviceContinuations[identifier]?.yield((identifier, .updatedChunk(chunk, status: .receivedAndPendingUpload)))
    }
}
