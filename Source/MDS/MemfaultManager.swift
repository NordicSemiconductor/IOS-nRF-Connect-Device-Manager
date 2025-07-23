/*
 * Copyright (c) 2025 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

/// Main manager for Memfault MDS operations
public class MemfaultManager: NSObject {
    
    // MARK: - Properties
    
    public var connectedDevice: MemfaultDevice?
    public var isScanning: Bool = false
    public var uploadProgress: Double = 0.0
    
    private var centralManager: CBCentralManager?
    private var currentPeripheral: CBPeripheral?
    
    // Callbacks
    public var onDeviceConnected: ((MemfaultDevice) -> Void)?
    public var onDeviceDisconnected: ((MemfaultDevice) -> Void)?
    public var onDeviceInfoUpdated: ((MemfaultDevice) -> Void)?
    public var onChunkReceived: ((MemfaultChunk) -> Void)?
    public var onChunkUploaded: ((MemfaultChunk) -> Void)?
    public var onError: ((MemfaultError) -> Void)?
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        
        // Listen for MDS data export notifications from the transport
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMDSDataExportNotification(_:)),
            name: Notification.Name("MDSDataExportNotification"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Connect to a device that already has a BLE connection through McuMgrBleTransport
    public func connectToDevice(peripheral: CBPeripheral, transport: McuMgrBleTransport? = nil) {
        print("MemfaultManager: Connecting to device \(peripheral.identifier)")
        print("MemfaultManager: Current peripheral state: \(peripheral.state)")
        print("MemfaultManager: Current peripheral delegate: \(String(describing: peripheral.delegate))")
        
        currentPeripheral = peripheral
        
        let device = MemfaultDevice(peripheral: peripheral)
        connectedDevice = device
        
        // Check if peripheral is already connected
        if peripheral.state == .connected {
            print("MemfaultManager: Peripheral already connected, checking for services")
            
            // If we have a transport, try to get MDS/DIS services from it
            if let transport = transport {
                print("MemfaultManager: Checking transport for discovered MDS/DIS services")
                checkTransportServices(transport, device: device)
            } else if let services = peripheral.services {
                print("MemfaultManager: Found \(services.count) existing services: \(services.map { $0.uuid.uuidString })")
                handleExistingServices(services, peripheral: peripheral)
            } else {
                print("MemfaultManager: No transport provided and no existing services found")
                onError?(.mdsServiceNotFound)
            }
        } else {
            print("MemfaultManager: Peripheral not connected (state: \(peripheral.state))")
            onError?(.mdsServiceNotFound)
        }
    }
    
    private func handleExistingServices(_ services: [CBService], peripheral: CBPeripheral) {
        // Process already discovered services
        for service in services {
            if service.uuid == .mdsService {
                print("MemfaultManager: Found existing MDS service")
                connectedDevice?.mdsService = service
                
                // Check if characteristics are already discovered
                if let characteristics = service.characteristics {
                    print("MemfaultManager: MDS service has \(characteristics.count) existing characteristics")
                    handleMDSCharacteristics(characteristics, service: service, peripheral: peripheral)
                } else {
                    print("MemfaultManager: Need to discover MDS characteristics")
                    // We'd need to discover characteristics but can't without delegate
                }
            } else if service.uuid == .deviceInformationService {
                print("MemfaultManager: Found existing DIS service")
                connectedDevice?.disService = service
                
                // Check if characteristics are already discovered
                if let characteristics = service.characteristics {
                    print("MemfaultManager: DIS service has \(characteristics.count) existing characteristics")
                    handleDISCharacteristics(characteristics, service: service, peripheral: peripheral)
                } else {
                    print("MemfaultManager: Need to discover DIS characteristics")
                    // We'd need to discover characteristics but can't without delegate
                }
            }
        }
        
        // Check if we found what we need
        let hasMDS = connectedDevice?.mdsService != nil
        let hasDIS = connectedDevice?.disService != nil
        
        print("MemfaultManager: Service discovery summary - MDS: \(hasMDS), DIS: \(hasDIS)")
        
        if hasMDS {
            connectedDevice?.isConnected = true
            onDeviceConnected?(connectedDevice!)
        } else if hasDIS {
            // DIS without MDS is still useful
            connectedDevice?.isConnected = true
            onDeviceConnected?(connectedDevice!)
        } else {
            onError?(.mdsServiceNotFound)
        }
    }
    
    private func checkTransportServices(_ transport: McuMgrBleTransport, device: MemfaultDevice) {
        print("MemfaultManager: Checking transport for MDS and DIS services")
        print("MemfaultManager: Transport state: \(transport.state)")
        
        // If transport is not connected yet, wait a moment and retry
        if transport.state != .connected {
            print("MemfaultManager: Transport not fully connected, waiting...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkTransportServices(transport, device: device)
            }
            return
        }
        
        // Check for MDS service
        if let mdsService = transport.mdsService {
            print("MemfaultManager: Found MDS service from transport")
            device.mdsService = mdsService
            
            // Get MDS characteristics from transport
            let mdsCharacteristics = transport.mdsCharacteristics
            print("MemfaultManager: Found \(mdsCharacteristics.count) MDS characteristics")
            handleMDSCharacteristics(mdsCharacteristics, service: mdsService, peripheral: device.peripheral)
        } else {
            print("MemfaultManager: No MDS service found in transport")
        }
        
        // Check for DIS service
        if let disService = transport.disService {
            print("MemfaultManager: Found DIS service from transport")
            device.disService = disService
            
            // Get DIS characteristics from transport
            let disCharacteristics = transport.disCharacteristics
            print("MemfaultManager: Found \(disCharacteristics.count) DIS characteristics")
            handleDISCharacteristics(disCharacteristics, service: disService, peripheral: device.peripheral)
        } else {
            print("MemfaultManager: No DIS service found in transport")
        }
        
        // Check if we found what we need
        let hasMDS = device.mdsService != nil
        let hasDIS = device.disService != nil
        
        print("MemfaultManager: Service check summary - MDS: \(hasMDS), DIS: \(hasDIS)")
        
        if hasMDS || hasDIS {
            device.isConnected = true
            onDeviceConnected?(device)
            
            // Read values from DIS characteristics if available
            if hasDIS {
                readDISCharacteristics(device: device)
            }
            
            // Read values from MDS characteristics if available
            if hasMDS {
                readMDSCharacteristics(device: device)
            }
        } else {
            print("MemfaultManager: No MDS or DIS services found")
            onError?(.mdsServiceNotFound)
        }
    }
    
    private func readDISCharacteristics(device: MemfaultDevice) {
        guard let peripheral = currentPeripheral else { return }
        
        print("MemfaultManager: Reading DIS characteristics")
        
        // Since we can't be the delegate, we'll read the values synchronously if they're already cached
        if let char = device.manufacturerNameCharacteristic, let value = char.value {
            handleManufacturerNameUpdate(value, device: device)
        } else if let char = device.manufacturerNameCharacteristic {
            print("MemfaultManager: Requesting read of manufacturer name")
            peripheral.readValue(for: char)
        }
        
        if let char = device.modelNumberCharacteristic, let value = char.value {
            handleModelNumberUpdate(value, device: device)
        } else if let char = device.modelNumberCharacteristic {
            print("MemfaultManager: Requesting read of model number")
            peripheral.readValue(for: char)
        }
        
        if let char = device.hardwareRevisionCharacteristic, let value = char.value {
            handleHardwareRevisionUpdate(value, device: device)
        } else if let char = device.hardwareRevisionCharacteristic {
            print("MemfaultManager: Requesting read of hardware revision")
            peripheral.readValue(for: char)
        }
        
        if let char = device.firmwareRevisionCharacteristic, let value = char.value {
            handleFirmwareRevisionUpdate(value, device: device)
        } else if let char = device.firmwareRevisionCharacteristic {
            print("MemfaultManager: Requesting read of firmware revision")
            peripheral.readValue(for: char)
        }
        
        if let char = device.softwareRevisionCharacteristic, let value = char.value {
            handleSoftwareRevisionUpdate(value, device: device)
        } else if let char = device.softwareRevisionCharacteristic {
            print("MemfaultManager: Requesting read of software revision")
            peripheral.readValue(for: char)
        }
        
        // Since we're not the delegate, we'll set a timer to check for values later
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkDISValues(device: device)
        }
    }
    
    private func readMDSCharacteristics(device: MemfaultDevice) {
        guard let peripheral = currentPeripheral else { return }
        
        print("MemfaultManager: Reading MDS characteristics")
        
        // Read Device Identifier
        if let char = device.deviceIdentifierCharacteristic {
            print("MemfaultManager: Requesting read of MDS device identifier")
            if let value = char.value {
                print("MemfaultManager: Device ID value already available")
                if let identifier = String(data: value, encoding: .utf8) {
                    device.deviceIdentifier = identifier
                    print("MemfaultManager: Device identifier from cache: '\(identifier)'")
                }
            } else {
                peripheral.readValue(for: char)
            }
        }
        
        // Read Data URI
        if let char = device.dataURICharacteristic {
            print("MemfaultManager: Requesting read of MDS data URI")
            if let value = char.value {
                print("MemfaultManager: Data URI value already available")
                if let uri = String(data: value, encoding: .utf8) {
                    device.dataURI = uri
                    print("MemfaultManager: Data URI from cache: '\(uri)'")
                }
            } else {
                peripheral.readValue(for: char)
            }
        }
        
        // Read Authorization data (contains project key!)
        if let char = device.authenticationCharacteristic {
            print("MemfaultManager: Requesting read of MDS authorization (contains project key)")
            // Check if value is already available
            if let value = char.value {
                print("MemfaultManager: Authorization value already available, processing it")
                // Process the authorization value directly
                if let authString = String(data: value, encoding: .utf8) {
                    print("MemfaultManager: Processing cached authorization value: '\(authString)'")
                    let prefix = "Memfault-Project-Key:"
                    if authString.hasPrefix(prefix) {
                        let projectKey = authString.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces)
                        if !projectKey.isEmpty {
                            device.projectKey = projectKey
                            print("MemfaultManager: Extracted project key: \(projectKey)")
                            onDeviceInfoUpdated?(device)
                        }
                    }
                }
            } else {
                print("MemfaultManager: No cached value, requesting read")
                peripheral.readValue(for: char)
            }
        }
        
        // Don't read data export - that's for notifications only
    }
    
    private func checkDISValues(device: MemfaultDevice) {
        print("MemfaultManager: Checking DIS values after delay")
        var hasUpdates = false
        
        if let char = device.manufacturerNameCharacteristic, let value = char.value {
            handleManufacturerNameUpdate(value, device: device)
            hasUpdates = true
        }
        
        if let char = device.modelNumberCharacteristic, let value = char.value {
            handleModelNumberUpdate(value, device: device)
            hasUpdates = true
        }
        
        if let char = device.hardwareRevisionCharacteristic, let value = char.value {
            handleHardwareRevisionUpdate(value, device: device)
            hasUpdates = true
        }
        
        if let char = device.firmwareRevisionCharacteristic, let value = char.value {
            handleFirmwareRevisionUpdate(value, device: device)
            hasUpdates = true
        }
        
        if let char = device.softwareRevisionCharacteristic, let value = char.value {
            handleSoftwareRevisionUpdate(value, device: device)
            hasUpdates = true
        }
        
        if hasUpdates {
            onDeviceInfoUpdated?(device)
        }
    }
    
    private func requestServiceDiscovery(peripheral: CBPeripheral) {
        // Since we can't set ourselves as delegate without breaking the existing connection,
        // we need to work with what's already available or find another approach
        print("MemfaultManager: Cannot discover services without taking over delegate")
        print("MemfaultManager: Services should be discovered through transport layer")
        
        // For now, indicate that services are not available
        // In a real implementation, we might need to coordinate with the transport
        onError?(.mdsServiceNotFound)
    }
    
    private func handleMDSCharacteristics(_ characteristics: [CBCharacteristic], service: CBService, peripheral: CBPeripheral) {
        guard let device = connectedDevice else { return }
        
        print("MemfaultManager: Processing \(characteristics.count) MDS characteristics")
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case .mdsDeviceIdentifier:
                device.deviceIdentifierCharacteristic = characteristic
                print("MemfaultManager: Found MDS Device Identifier characteristic")
                
            case .mdsDataURI:
                device.dataURICharacteristic = characteristic
                print("MemfaultManager: Found MDS Data URI characteristic")
                
            case .mdsAuthorization:
                device.authenticationCharacteristic = characteristic
                print("MemfaultManager: Found MDS Authorization characteristic (contains project key!)")
                
            case .mdsDataExport:
                device.dataExportCharacteristic = characteristic
                print("MemfaultManager: Found MDS Data Export characteristic")
                
            default:
                print("MemfaultManager: Found unknown MDS characteristic: \(characteristic.uuid)")
            }
        }
    }
    
    private func handleDISCharacteristics(_ characteristics: [CBCharacteristic], service: CBService, peripheral: CBPeripheral) {
        guard let device = connectedDevice else { return }
        
        print("MemfaultManager: Processing \(characteristics.count) DIS characteristics")
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case .manufacturerNameString:
                device.manufacturerNameCharacteristic = characteristic
                print("MemfaultManager: Found DIS Manufacturer Name characteristic")
                
            case .modelNumberString:
                device.modelNumberCharacteristic = characteristic
                print("MemfaultManager: Found DIS Model Number characteristic")
                
            case .hardwareRevisionString:
                device.hardwareRevisionCharacteristic = characteristic
                print("MemfaultManager: Found DIS Hardware Revision characteristic")
                
            case .firmwareRevisionString:
                device.firmwareRevisionCharacteristic = characteristic
                print("MemfaultManager: Found DIS Firmware Revision characteristic")
                
            case .softwareRevisionString:
                device.softwareRevisionCharacteristic = characteristic
                print("MemfaultManager: Found DIS Software Revision characteristic")
                
            default:
                print("MemfaultManager: Found unknown DIS characteristic: \(characteristic.uuid)")
            }
        }
    }
    
    /// Disconnect from the current device
    public func disconnect() {
        guard let device = connectedDevice else { return }
        
        print("MemfaultManager: Disconnecting from device")
        
        // Stop notifications
        stopDataExportNotifications()
        
        // Clear device
        connectedDevice = nil
        currentPeripheral = nil
        
        onDeviceDisconnected?(device)
    }
    
    /// Upload pending chunks to Memfault
    public func uploadPendingChunks() {
        guard let device = connectedDevice else { return }
        
        let pendingChunks = device.pendingChunks
        guard !pendingChunks.isEmpty else {
            print("MemfaultManager: No pending chunks to upload")
            return
        }
        
        print("MemfaultManager: Uploading \(pendingChunks.count) chunks")
        uploadChunks(pendingChunks)
    }
    
    /// Start streaming diagnostic data from the device
    public func startDataStreaming() {
        guard let device = connectedDevice,
              let dataExportChar = device.dataExportCharacteristic,
              let peripheral = currentPeripheral else {
            onError?(.deviceNotConnected)
            return
        }
        
        print("MemfaultManager: Starting data streaming")
        
        // Enable streaming by writing 0x01 to the Data Export characteristic
        let enableStreamingCommand = Data([0x01])
        
        // Check characteristic properties to determine write type
        if dataExportChar.properties.contains(.write) {
            peripheral.writeValue(enableStreamingCommand, for: dataExportChar, type: .withResponse)
            print("MemfaultManager: Sent enable streaming command (0x01) with response")
        } else if dataExportChar.properties.contains(.writeWithoutResponse) {
            peripheral.writeValue(enableStreamingCommand, for: dataExportChar, type: .withoutResponse)
            print("MemfaultManager: Sent enable streaming command (0x01) without response")
        } else {
            print("MemfaultManager: ERROR - Data Export characteristic doesn't support any write type!")
        }
        
        device.isStreamingData = true
        onDeviceInfoUpdated?(device)
    }
    
    /// Stop streaming diagnostic data
    public func stopDataStreaming() {
        guard let device = connectedDevice,
              let dataExportChar = device.dataExportCharacteristic,
              let peripheral = currentPeripheral else { return }
        
        print("MemfaultManager: Stopping data streaming")
        
        // Disable streaming by writing 0x00 to the Data Export characteristic
        let disableStreamingCommand = Data([0x00])
        peripheral.writeValue(disableStreamingCommand, for: dataExportChar, type: .withoutResponse)
        print("MemfaultManager: Sent disable streaming command (0x00)")
        
        device.isStreamingData = false
        onDeviceInfoUpdated?(device)
    }
    
    // MARK: - Private Methods
    
    private func stopDataExportNotifications() {
        guard let device = connectedDevice,
              let characteristic = device.dataExportCharacteristic else { return }
        
        currentPeripheral?.setNotifyValue(false, for: characteristic)
        device.isStreamingData = false
    }
    
    private func uploadChunks(_ chunks: [MemfaultChunk]) {
        guard let device = connectedDevice,
              let projectKey = device.projectKey else {
            print("MemfaultManager: Missing project key for upload")
            return
        }
        
        uploadProgress = 0.0
        let totalChunks = chunks.count
        var completedChunks = 0
        
        for chunk in chunks {
            chunk.uploadStatus = .uploading
            
            uploadChunkToMemfault(chunk, projectKey: projectKey) { [weak self] result in
                DispatchQueue.main.async {
                    completedChunks += 1
                    self?.uploadProgress = Double(completedChunks) / Double(totalChunks)
                    
                    switch result {
                    case .success:
                        chunk.uploadStatus = .success
                        device.removeChunk(chunk)
                        print("MemfaultManager: Chunk \(chunk.sequenceNumber) uploaded successfully")
                        self?.onChunkUploaded?(chunk)
                        
                    case .failure(let error):
                        chunk.uploadStatus = .error(error)
                        print("MemfaultManager: Failed to upload chunk \(chunk.sequenceNumber): \(error)")
                        self?.onError?(.uploadFailed(error))
                    }
                }
            }
        }
    }
    
    private func uploadChunkToMemfault(_ chunk: MemfaultChunk, 
                                     projectKey: String, 
                                     completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we should use the device's data URI instead
        var urlString = "https://api.memfault.com/api/v0/chunks"
        if let device = connectedDevice, let dataURI = device.dataURI, !dataURI.isEmpty {
            print("MemfaultManager: Using device-provided data URI: \(dataURI)")
            urlString = dataURI
        } else {
            print("MemfaultManager: Using default Memfault chunks URL: \(urlString)")
        }
        
        guard let url = URL(string: urlString) else {
            print("MemfaultManager: Invalid URL: \(urlString)")
            completion(.failure(MemfaultError.networkError(NSError(domain: "InvalidURL", code: 0))))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(projectKey, forHTTPHeaderField: "Memfault-Project-Key")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = chunk.data
        
        print("MemfaultManager: HTTP Request Details:")
        print("  - URL: \(url.absoluteString)")
        print("  - Method: POST")
        print("  - Headers:")
        print("    - Memfault-Project-Key: \(projectKey)")
        print("    - Content-Type: application/octet-stream")
        print("  - Body size: \(chunk.data.count) bytes")
        print("  - Body hex (first 20 bytes): \(chunk.data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("MemfaultManager: Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("MemfaultManager: HTTP Response:")
                print("  - Status Code: \(httpResponse.statusCode)")
                print("  - Headers: \(httpResponse.allHeaderFields)")
                
                if let responseData = data {
                    print("  - Response body size: \(responseData.count) bytes")
                    if let responseString = String(data: responseData, encoding: .utf8) {
                        print("  - Response body: \(responseString)")
                    }
                }
                
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                    print("MemfaultManager: Chunk uploaded successfully!")
                    completion(.success(()))
                } else {
                    print("MemfaultManager: Upload failed with status \(httpResponse.statusCode)")
                    let errorMessage = "HTTP \(httpResponse.statusCode)"
                    if let responseData = data, let responseString = String(data: responseData, encoding: .utf8) {
                        print("MemfaultManager: Error response: \(responseString)")
                    }
                    let error = NSError(domain: "MemfaultAPI", 
                                      code: httpResponse.statusCode, 
                                      userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    internal func parseChunkData(_ data: Data) -> MemfaultChunk? {
        // MDS chunk packet format per spec:
        // Byte 0: Sequence counter (bits 0-4) and reserved bits (5-7)
        // Byte 1+: Chunk payload
        
        guard data.count > 1 else { 
            print("MemfaultManager: Chunk data too small (size: \(data.count))")
            return nil 
        }
        
        // Extract sequence number from first byte (bits 0-4)
        let sequenceByte = data[0]
        let sequenceNumber = UInt16(sequenceByte & 0x1F) // Mask to get bits 0-4
        
        // Extract the actual chunk payload (skip the sequence byte)
        let chunkPayload = data.subdata(in: 1..<data.count)
        
        print("MemfaultManager: Parsed MDS packet - sequence: \(sequenceNumber), payload size: \(chunkPayload.count)")
        print("MemfaultManager: Sequence byte: 0x\(String(format: "%02x", sequenceByte))")
        
        // Return the payload without the MDS packet header
        return MemfaultChunk(sequenceNumber: sequenceNumber, data: chunkPayload)
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleMDSDataExportNotification(_ notification: Notification) {
        print("MemfaultManager: *** NOTIFICATION RECEIVED IN MEMFAULT MANAGER ***")
        
        guard let userInfo = notification.userInfo else {
            print("MemfaultManager: No userInfo in notification")
            return
        }
        
        guard let data = userInfo["data"] as? Data else {
            print("MemfaultManager: No data in notification userInfo")
            return
        }
        
        guard let peripheral = userInfo["peripheral"] as? CBPeripheral else {
            print("MemfaultManager: No peripheral in notification userInfo")
            return
        }
        
        guard let device = connectedDevice else {
            print("MemfaultManager: No connected device")
            return
        }
        
        guard device.peripheral.identifier == peripheral.identifier else {
            print("MemfaultManager: Peripheral mismatch - received: \(peripheral.identifier), expected: \(device.peripheral.identifier)")
            return
        }
        
        print("MemfaultManager: Processing MDS data export: \(data.count) bytes")
        print("MemfaultManager: First 10 bytes: \(data.prefix(10).map { String(format: "%02x", $0) }.joined(separator: " "))")
        handleDataExportUpdate(data, device: device)
    }
}