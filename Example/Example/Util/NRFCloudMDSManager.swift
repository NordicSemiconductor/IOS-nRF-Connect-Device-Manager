/*
 * Copyright (c) 2024 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

// MARK: - NRFCloudMDSManagerDelegate

protocol NRFCloudMDSManagerDelegate: AnyObject {
    func mdsManager(_ manager: NRFCloudMDSManager, didUpdateStatus status: String)
    func mdsManager(_ manager: NRFCloudMDSManager, didReceiveChunk number: Int, forwarded: Int)
    func mdsManager(_ manager: NRFCloudMDSManager, didFailWithError error: Error)
    func mdsManager(_ manager: NRFCloudMDSManager, didDiscoverConfiguration projectKey: String?, deviceId: String?)
}

// MARK: - NRFCloudMDSManager

/// Manager for handling Memfault Diagnostic Service (MDS) operations
/// This class manages the discovery, configuration, and data forwarding for MDS over BLE
class NRFCloudMDSManager: NSObject {
    
    // MARK: - Constants
    
    private enum MDSConstants {
        static let serviceUUID = "54220000-F6A5-4007-A371-722F4EBD8436"
        static let deviceIdCharUUID = "54220002-F6A5-4007-A371-722F4EBD8436"
        static let authCharUUID = "54220004-F6A5-4007-A371-722F4EBD8436"
        static let dataExportCharUUID = "54220005-F6A5-4007-A371-722F4EBD8436"
        static let maxDiscoveryRetries = 3
        static let discoveryRetryDelay: TimeInterval = 2.0
        static let configReadDelay: TimeInterval = 0.5
        static let memfaultChunksEndpoint = "https://chunks.memfault.com/api/v0/chunks/"
    }
    
    // MARK: - Properties
    
    weak var delegate: NRFCloudMDSManagerDelegate?
    
    private weak var peripheral: CBPeripheral?
    private var mdsService: CBService?
    private var mdsDataExportCharacteristic: CBCharacteristic?
    private var projectKey: String?
    private var deviceId: String?
    private var serviceDiscoveryRetryCount = 0
    private var isDiscovering = false  // Flag to prevent duplicate discoveries
    
    // MARK: - Public Properties
    
    private(set) var isStreaming = false
    private(set) var chunksReceived = 0
    private(set) var chunksForwarded = 0
    
    // MARK: - Initialization
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start MDS discovery and streaming
    func start() {
        guard let peripheral = peripheral else {
            delegate?.mdsManager(self, didUpdateStatus: "No peripheral")
            return
        }
        
        // Check connection state
        if peripheral.state != .connected {
            delegate?.mdsManager(self, didUpdateStatus: "Disconnected")
            return
        }
        
        // If already streaming, just update status with current counts
        if isStreaming {
            if chunksReceived > 0 || chunksForwarded > 0 {
                // Update delegate with current counts
                delegate?.mdsManager(self, didReceiveChunk: chunksReceived, forwarded: chunksForwarded)
            } else {
                delegate?.mdsManager(self, didUpdateStatus: "MDS streaming enabled - waiting for chunks")
            }
            return
        }
        
        // If we already have the service discovered, resume streaming
        if mdsDataExportCharacteristic != nil {
            // Update with current counts if any
            if chunksReceived > 0 || chunksForwarded > 0 {
                delegate?.mdsManager(self, didReceiveChunk: chunksReceived, forwarded: chunksForwarded)
            } else {
                delegate?.mdsManager(self, didUpdateStatus: "MDS ready")
            }
            // Re-enable streaming in case it was stopped
            enableMDSStreaming(peripheral: peripheral)
            return
        }
        
        // Set ourselves as the peripheral delegate to receive notifications
        peripheral.delegate = self
        
        // Start service discovery
        delegate?.mdsManager(self, didUpdateStatus: "Discovering MDS service...")
        discoverMDSService(peripheral: peripheral)
    }
    
    /// Stop MDS streaming and cleanup
    func stop() {
        guard let peripheral = peripheral,
              let dataExportChar = mdsDataExportCharacteristic,
              isStreaming else {
            return
        }
        
        // Disable streaming mode by writing 0x00
        let disableData = Data([0x00])
        print("[MDS] Disabling MDS streaming mode")
        peripheral.writeValue(disableData, for: dataExportChar, type: .withResponse)
        isStreaming = false
        
        // Clear delegate to stop receiving notifications
        if peripheral.delegate === self {
            peripheral.delegate = nil
        }
    }
    
    /// Reset state (useful when connection is lost)
    func reset() {
        isStreaming = false
        isDiscovering = false
        mdsService = nil
        mdsDataExportCharacteristic = nil
        serviceDiscoveryRetryCount = 0
        // Don't reset counters - they should persist for the session
        // chunksReceived = 0
        // chunksForwarded = 0
        projectKey = nil
        deviceId = nil
    }
    
    /// Reset counters only (call this when starting a new session)
    func resetCounters() {
        chunksReceived = 0
        chunksForwarded = 0
    }
    
    // MARK: - Private Methods
    
    private func discoverMDSService(peripheral: CBPeripheral) {
        print("[MDS] Available services: \(peripheral.services?.map { $0.uuid.uuidString } ?? [])")
        
        // Prevent concurrent discoveries
        if isDiscovering {
            print("[MDS] Discovery already in progress, skipping")
            return
        }
        
        // Check if we already have MDS service and characteristic configured
        if mdsService != nil && mdsDataExportCharacteristic != nil {
            print("[MDS] MDS already configured, skipping discovery")
            // Just ensure streaming is enabled
            enableMDSStreaming(peripheral: peripheral)
            return
        }
        
        // If services haven't been fully discovered, trigger discovery
        if peripheral.services == nil || peripheral.services?.count == 1 {
            // Check if we already have MDS service stored (shouldn't happen, but be safe)
            if mdsService != nil {
                print("[MDS] Service already stored, skipping discovery")
                return
            }
            
            // Limit retries to prevent infinite loops
            if serviceDiscoveryRetryCount >= MDSConstants.maxDiscoveryRetries {
                print("[MDS] Max service discovery retries reached")
                delegate?.mdsManager(self, didUpdateStatus: "Service discovery failed")
                serviceDiscoveryRetryCount = 0
                return
            }
            
            serviceDiscoveryRetryCount += 1
            print("[MDS] Limited services found, triggering full discovery (attempt \(serviceDiscoveryRetryCount))...")
            isDiscovering = true  // Set flag before starting discovery
            peripheral.discoverServices(nil)
            
            // The didDiscoverServices delegate callback will handle the response
            // No need for delayed retry here
            return
        }
        
        // Reset retry count on successful discovery
        serviceDiscoveryRetryCount = 0
        
        // Look for MDS service
        if let mdsService = peripheral.services?.first(where: { 
            $0.uuid.uuidString.uppercased() == MDSConstants.serviceUUID 
        }) {
            self.mdsService = mdsService
            print("[MDS] Found MDS service")
            
            // Check if characteristics are already discovered
            if mdsService.characteristics == nil {
                print("[MDS] Discovering MDS characteristics...")
                peripheral.discoverCharacteristics(nil, for: mdsService)
                // The discovery will complete in the peripheral delegate callback
                // Don't call setupMDSCharacteristics here - wait for delegate
            } else {
                setupMDSCharacteristics(peripheral: peripheral)
            }
        } else {
            print("[MDS] MDS service not found after full discovery")
            print("[MDS] All available services: \(peripheral.services?.map { $0.uuid.uuidString } ?? [])")
            delegate?.mdsManager(self, didUpdateStatus: "MDS not available")
        }
    }
    
    private func setupMDSCharacteristics(peripheral: CBPeripheral) {
        guard let mdsService = self.mdsService else { return }
        
        // Prevent duplicate setup
        if mdsDataExportCharacteristic != nil {
            print("[MDS] Characteristics already set up, skipping")
            return
        }
        
        // Find Data Export characteristic
        if let dataExportChar = mdsService.characteristics?.first(where: { 
            $0.uuid.uuidString.uppercased() == MDSConstants.dataExportCharUUID 
        }) {
            self.mdsDataExportCharacteristic = dataExportChar
            print("[MDS] Found Data Export characteristic")
            
            // Subscribe to notifications
            if dataExportChar.properties.contains(.notify) && !dataExportChar.isNotifying {
                print("[MDS] Subscribing to Data Export notifications")
                peripheral.setNotifyValue(true, for: dataExportChar)
            } else if dataExportChar.isNotifying {
                print("[MDS] Already subscribed to notifications")
            }
            
            // Read project key and device ID from other characteristics
            readMDSConfiguration(peripheral: peripheral, service: mdsService)
            
            // Enable streaming after a short delay to ensure subscription is active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.enableMDSStreaming(peripheral: peripheral)
            }
        } else {
            print("[MDS] Data Export characteristic not found")
            delegate?.mdsManager(self, didUpdateStatus: "MDS Data Export not found")
        }
    }
    
    private func readMDSConfiguration(peripheral: CBPeripheral, service: CBService) {
        // Read Device ID
        if let deviceIdChar = service.characteristics?.first(where: { 
            $0.uuid.uuidString.uppercased() == MDSConstants.deviceIdCharUUID 
        }) {
            peripheral.readValue(for: deviceIdChar)
        }
        
        // Read Authorization/Project Key
        if let authChar = service.characteristics?.first(where: { 
            $0.uuid.uuidString.uppercased() == MDSConstants.authCharUUID 
        }) {
            peripheral.readValue(for: authChar)
        }
        
        // Wait for reads to complete then process
        DispatchQueue.main.asyncAfter(deadline: .now() + MDSConstants.configReadDelay) { [weak self] in
            guard let self = self, let service = self.mdsService else { return }
            
            // Extract Device ID
            if let deviceIdChar = service.characteristics?.first(where: { 
                $0.uuid.uuidString.uppercased() == MDSConstants.deviceIdCharUUID 
            }),
               let deviceIdData = deviceIdChar.value,
               let deviceIdString = String(data: deviceIdData, encoding: .utf8) {
                self.deviceId = deviceIdString
                print("[MDS] Device ID: \(deviceIdString)")
            }
            
            // Extract Project Key from Authorization characteristic
            if let authChar = service.characteristics?.first(where: { 
                $0.uuid.uuidString.uppercased() == MDSConstants.authCharUUID 
            }),
               let authData = authChar.value,
               let authString = String(data: authData, encoding: .utf8) {
                // Parse "Memfault-Project-Key:xxxxx" format
                if authString.contains("Memfault-Project-Key:") {
                    let components = authString.split(separator: ":")
                    if components.count >= 2 {
                        self.projectKey = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        print("[MDS] Project Key found")
                    }
                }
            }
            
            // Notify delegate of discovered configuration
            self.delegate?.mdsManager(self, didDiscoverConfiguration: self.projectKey, deviceId: self.deviceId)
        }
    }
    
    private func enableMDSStreaming(peripheral: CBPeripheral) {
        guard let dataExportChar = mdsDataExportCharacteristic else {
            print("[MDS] Cannot enable streaming - characteristic not found")
            return
        }
        
        // Skip if already streaming
        if isStreaming {
            print("[MDS] Streaming already enabled")
            return
        }
        
        // Enable streaming mode by writing 0x01
        let enableData = Data([0x01])
        print("[MDS] Enabling MDS streaming mode")
        peripheral.writeValue(enableData, for: dataExportChar, type: .withResponse)
        isStreaming = true
        
        // Update status based on whether we have chunks already
        if chunksReceived > 0 || chunksForwarded > 0 {
            delegate?.mdsManager(self, didReceiveChunk: chunksReceived, forwarded: chunksForwarded)
        } else {
            delegate?.mdsManager(self, didUpdateStatus: "MDS streaming enabled - waiting for chunks")
        }
    }
    
    private func forwardChunkToMemfault(data: Data) {
        guard let projectKey = projectKey,
              let deviceId = deviceId else {
            print("[MDS] Cannot forward chunk - missing project key or device ID")
            delegate?.mdsManager(self, didUpdateStatus: "Missing config - chunks: \(chunksReceived)")
            return
        }
        
        // Create the Memfault chunks endpoint URL
        let urlString = "\(MDSConstants.memfaultChunksEndpoint)\(deviceId)"
        guard let url = URL(string: urlString) else {
            print("[MDS] Invalid URL for chunk forwarding")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(projectKey, forHTTPHeaderField: "Memfault-Project-Key")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        // Send the chunk
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[MDS] Failed to forward chunk: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.delegate?.mdsManager(self, didUpdateStatus: "Forward failed - chunks: \(self.chunksReceived)")
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 202 {
                    self.chunksForwarded += 1
                    print("[MDS] Successfully forwarded chunk #\(self.chunksForwarded)")
                    DispatchQueue.main.async {
                        self.delegate?.mdsManager(self, didReceiveChunk: self.chunksReceived, forwarded: self.chunksForwarded)
                    }
                } else {
                    print("[MDS] Chunk forward failed with status: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        self.delegate?.mdsManager(self, didUpdateStatus: "Forward error (\(httpResponse.statusCode)) - chunks: \(self.chunksReceived)")
                    }
                }
            }
        }
        task.resume()
    }
}

// MARK: - CBPeripheralDelegate

extension NRFCloudMDSManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Clear discovery flag
        isDiscovering = false
        
        guard error == nil else {
            print("[MDS] Error discovering services: \(error!)")
            delegate?.mdsManager(self, didFailWithError: error!)
            return
        }
        
        print("[MDS] Services discovered successfully")
        // Continue with MDS service discovery
        discoverMDSService(peripheral: peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("[MDS] Error discovering characteristics: \(error!)")
            delegate?.mdsManager(self, didFailWithError: error!)
            return
        }
        
        // Continue with MDS setup after characteristic discovery
        if service.uuid.uuidString.uppercased() == MDSConstants.serviceUUID {
            setupMDSCharacteristics(peripheral: peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Check if this is an MDS Data Export notification
        guard characteristic.uuid.uuidString.uppercased() == MDSConstants.dataExportCharUUID,
              let data = characteristic.value else {
            return
        }
        
        chunksReceived += 1
        print("[MDS] Received chunk #\(chunksReceived): \(data.count) bytes")
        
        // Notify delegate immediately when chunk is received
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.mdsManager(self, didReceiveChunk: self.chunksReceived, forwarded: self.chunksForwarded)
        }
        
        // Forward the chunk to Memfault cloud
        forwardChunkToMemfault(data: data)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            print("[MDS] Error updating notification state: \(error!)")
            delegate?.mdsManager(self, didFailWithError: error!)
        } else if characteristic.isNotifying {
            print("[MDS] Notifications enabled for characteristic: \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[MDS] Error writing value: \(error)")
            delegate?.mdsManager(self, didFailWithError: error)
        }
    }
}