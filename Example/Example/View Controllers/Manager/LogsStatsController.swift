/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary
import CoreBluetooth

// MARK: - LogsStatsController

final class LogsStatsController: UITableViewController {
    
    // MARK: @IBOutlet(s)
    
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var mcuMgrParams: UILabel!
    @IBOutlet weak var bootloaderName: UILabel!
    @IBOutlet weak var bootloaderMode: UILabel!
    @IBOutlet weak var bootloaderSlot: UILabel!
    @IBOutlet weak var kernel: UILabel!
    @IBOutlet weak var stats: UILabel!
    @IBOutlet weak var refreshAction: UIButton!
    @IBOutlet weak var chunksLabel: UILabel!  // Connect this to the chunks label in storyboard
    
    // MARK: @IBAction(s)
    
    @IBAction func refreshTapped(_ sender: UIButton) {
        statsManager.list(callback: statsCallback)
    }
    
    // MARK: statsCallback
    
    private lazy var statsCallback: McuMgrCallback<McuMgrStatsListResponse> = { [weak self] response, error in
        guard let self else { return }
        defer {
            onStatsChanged()
        }
        
        guard let response else {
            stats.textColor = .systemRed
            stats.text = error?.localizedDescription ?? "Unknown Error"
            return
        }
        
        stats.text = ""
        stats.textColor = .primary
        
        guard let modules = response.names, !modules.isEmpty else {
            stats.text = "No stats found"
            return
        }
        
        for module in modules {
            statsManager.read(module: module, callback: { [unowned self] (moduleStats, moduleError) in
                self.stats.text! += self.moduleStatsString(module, stats: moduleStats, error: moduleError)
                self.onStatsChanged()
            })
        }
    }
    
    // MARK: Private Properties
    
    private var statsManager: StatsManager!
    
    // MDS Observability properties
    private var chunksReceived = 0
    private var chunksForwarded = 0
    private var mdsService: CBService?
    private var mdsDataExportCharacteristic: CBCharacteristic?
    private var projectKey: String?
    private var deviceId: String?
    private var isStreamingEnabled = false
    private var serviceDiscoveryRetryCount = 0
    
    // MARK: UIViewController
    
    override func viewDidAppear(_ animated: Bool) {
        guard let baseController = parent as? BaseViewController else { return }
        baseController.deviceStatusDelegate = self
        
        let transport: McuMgrTransport! = baseController.transport
        statsManager = StatsManager(transport: transport)
        statsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        
        // Set up MDS chunk forwarding
        setupMDSChunkForwarding()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Stop MDS streaming when leaving the view
        stopMDSStreaming()
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: Notification.Name("MDSDataExportNotification"), object: nil)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
}

// MARK: - Private

private extension LogsStatsController {
    
    func setupMDSChunkForwarding() {
        // Listen for MDS data export notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMDSDataNotification(_:)),
            name: Notification.Name("MDSDataExportNotification"),
            object: nil
        )
        
        // Get the BLE transport and peripheral
        guard let baseController = parent as? BaseViewController,
              let transport = baseController.transport as? McuMgrBleTransport,
              let peripheral = transport.peripheral else {
            print("[MDS] Unable to get peripheral for MDS setup")
            updateChunksLabel(with: "MDS not available")
            return
        }
        
        // Find the MDS service
        discoverMDSService(peripheral: peripheral)
    }
    
    func discoverMDSService(peripheral: CBPeripheral) {
        print("[MDS] Available services: \(peripheral.services?.map { $0.uuid.uuidString } ?? [])")
        
        // If services haven't been fully discovered, trigger discovery
        if peripheral.services == nil || peripheral.services?.count == 1 {
            // Limit retries to prevent infinite loops
            if serviceDiscoveryRetryCount >= 3 {
                print("[MDS] Max service discovery retries reached")
                updateChunksLabel(with: "Service discovery failed")
                serviceDiscoveryRetryCount = 0
                return
            }
            
            serviceDiscoveryRetryCount += 1
            print("[MDS] Limited services found, triggering full discovery (attempt \(serviceDiscoveryRetryCount))...")
            peripheral.discoverServices(nil)
            
            // Wait for discovery then try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.discoverMDSService(peripheral: peripheral)
            }
            return
        }
        
        // Reset retry count on successful discovery
        serviceDiscoveryRetryCount = 0
        
        // Look for MDS service (UUID: 54220000-F6A5-4007-A371-722F4EBD8436)
        if let mdsService = peripheral.services?.first(where: { $0.uuid.uuidString.uppercased() == "54220000-F6A5-4007-A371-722F4EBD8436" }) {
            self.mdsService = mdsService
            print("[MDS] Found MDS service")
            
            // Check if characteristics are already discovered
            if mdsService.characteristics == nil {
                print("[MDS] Discovering MDS characteristics...")
                peripheral.discoverCharacteristics(nil, for: mdsService)
                // The discovery will complete in the peripheral delegate
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.setupMDSCharacteristics(peripheral: peripheral)
                }
            } else {
                setupMDSCharacteristics(peripheral: peripheral)
            }
        } else {
            print("[MDS] MDS service not found after full discovery")
            print("[MDS] All available services: \(peripheral.services?.map { $0.uuid.uuidString } ?? [])")
            updateChunksLabel(with: "MDS service not available")
        }
    }
    
    func setupMDSCharacteristics(peripheral: CBPeripheral) {
        guard let mdsService = self.mdsService else { return }
        
        // Find Data Export characteristic (UUID: 54220005-F6A5-4007-A371-722F4EBD8436)
        if let dataExportChar = mdsService.characteristics?.first(where: { $0.uuid.uuidString.uppercased() == "54220005-F6A5-4007-A371-722F4EBD8436" }) {
            self.mdsDataExportCharacteristic = dataExportChar
            print("[MDS] Found Data Export characteristic")
            
            // Subscribe to notifications
            if dataExportChar.properties.contains(.notify) {
                print("[MDS] Subscribing to Data Export notifications")
                peripheral.setNotifyValue(true, for: dataExportChar)
            }
            
            // Read project key and device ID from other characteristics
            readMDSConfiguration(peripheral: peripheral, service: mdsService)
            
            // Enable streaming after a short delay to ensure subscription is active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.enableMDSStreaming(peripheral: peripheral)
            }
        } else {
            print("[MDS] Data Export characteristic not found")
            updateChunksLabel(with: "MDS Data Export not found")
        }
    }
    
    func readMDSConfiguration(peripheral: CBPeripheral, service: CBService) {
        // Read Device ID (UUID: 54220002-F6A5-4007-A371-722F4EBD8436)
        if let deviceIdChar = service.characteristics?.first(where: { $0.uuid.uuidString.uppercased() == "54220002-F6A5-4007-A371-722F4EBD8436" }) {
            peripheral.readValue(for: deviceIdChar)
        }
        
        // Read Authorization/Project Key (UUID: 54220004-F6A5-4007-A371-722F4EBD8436)
        if let authChar = service.characteristics?.first(where: { $0.uuid.uuidString.uppercased() == "54220004-F6A5-4007-A371-722F4EBD8436" }) {
            peripheral.readValue(for: authChar)
        }
        
        // Wait for reads to complete then process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let service = self?.mdsService else { return }
            
            // Extract Device ID
            if let deviceIdChar = service.characteristics?.first(where: { $0.uuid.uuidString.uppercased() == "54220002-F6A5-4007-A371-722F4EBD8436" }),
               let deviceIdData = deviceIdChar.value,
               let deviceIdString = String(data: deviceIdData, encoding: .utf8) {
                self?.deviceId = deviceIdString
                print("[MDS] Device ID: \(deviceIdString)")
            }
            
            // Extract Project Key from Authorization characteristic
            if let authChar = service.characteristics?.first(where: { $0.uuid.uuidString.uppercased() == "54220004-F6A5-4007-A371-722F4EBD8436" }),
               let authData = authChar.value,
               let authString = String(data: authData, encoding: .utf8) {
                // Parse "Memfault-Project-Key:xxxxx" format
                if authString.contains("Memfault-Project-Key:") {
                    let components = authString.split(separator: ":")
                    if components.count >= 2 {
                        self?.projectKey = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        print("[MDS] Project Key found: \(self?.projectKey ?? "nil")")
                    }
                }
            }
            
            // Use stored project key if not found in MDS
            if self?.projectKey == nil {
                self?.projectKey = UserDefaults.standard.string(forKey: "memfault_project_key")
                print("[MDS] Using stored project key: \(self?.projectKey ?? "nil")")
            }
        }
    }
    
    func enableMDSStreaming(peripheral: CBPeripheral) {
        guard let dataExportChar = mdsDataExportCharacteristic else {
            print("[MDS] Cannot enable streaming - characteristic not found")
            return
        }
        
        // Enable streaming mode by writing 0x01
        let enableData = Data([0x01])
        print("[MDS] Enabling MDS streaming mode")
        peripheral.writeValue(enableData, for: dataExportChar, type: .withResponse)
        isStreamingEnabled = true
        updateChunksLabel(with: "MDS streaming enabled - waiting for chunks")
    }
    
    func stopMDSStreaming() {
        guard let baseController = parent as? BaseViewController,
              let transport = baseController.transport as? McuMgrBleTransport,
              let peripheral = transport.peripheral,
              let dataExportChar = mdsDataExportCharacteristic,
              isStreamingEnabled else {
            return
        }
        
        // Disable streaming mode by writing 0x00
        let disableData = Data([0x00])
        print("[MDS] Disabling MDS streaming mode")
        peripheral.writeValue(disableData, for: dataExportChar, type: .withResponse)
        isStreamingEnabled = false
    }
    
    @objc func handleMDSDataNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let data = userInfo["data"] as? Data else {
            return
        }
        
        chunksReceived += 1
        print("[MDS] Received chunk #\(chunksReceived): \(data.count) bytes")
        
        // Forward the chunk to Memfault cloud
        forwardChunkToMemfault(data: data)
    }
    
    func forwardChunkToMemfault(data: Data) {
        guard let projectKey = projectKey,
              let deviceId = deviceId else {
            print("[MDS] Cannot forward chunk - missing project key or device ID")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateChunksLabel(with: "Missing config - chunks: \(self.chunksReceived)")
            }
            return
        }
        
        // Create the Memfault chunks endpoint URL
        var request = URLRequest(url: URL(string: "https://chunks.memfault.com/api/v0/chunks/\(deviceId)")!)
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
                    self.updateChunksLabel(with: "Forward failed - chunks: \(self.chunksReceived)")
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 202 {
                    self.chunksForwarded += 1
                    print("[MDS] Successfully forwarded chunk #\(self.chunksForwarded)")
                    DispatchQueue.main.async {
                        self.updateChunksLabel()
                    }
                } else {
                    print("[MDS] Chunk forward failed with status: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        self.updateChunksLabel(with: "Forward error (\(httpResponse.statusCode)) - chunks: \(self.chunksReceived)")
                    }
                }
            }
        }
        task.resume()
    }
    
    func updateChunksLabel(with text: String? = nil) {
        guard let label = chunksLabel else { return }
        
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let customText = text {
                label.text = customText
            } else {
                label.text = "Chunks forwarded: \(self.chunksForwarded)"
            }
        }
    }
    
    func moduleStatsString(_ module: String, stats: McuMgrStatsResponse?, error: (any Error)?) -> String {
        var resultString = "\(module)"
        if let stats {
            if let group = stats.group {
                resultString += " (\(group))"
            }
            resultString += ":\n"
            if let fields = stats.fields {
                for field in fields {
                    resultString += "• \(field.key): \(field.value)\n"
                }
            } else {
                resultString += "• Empty\n"
            }
        } else {
            resultString += "\(error?.localizedDescription ?? "Unknown Error")\n"
        }
        
        resultString += "\n"
        return resultString
    }
    
    func onStatsChanged() {
        tableView.beginUpdates()
        tableView.setNeedsDisplay()
        tableView.endUpdates()
    }
}

// MARK: - DeviceStatusDelegate

extension LogsStatsController: DeviceStatusDelegate {
    
    func connectionStateDidChange(_ state: PeripheralState) {
        connectionStatus.text = state.description
        
        // Update chunks label based on connection state
        switch state {
        case .disconnected:
            updateChunksLabel(with: "Not connected")
            chunksReceived = 0
            chunksForwarded = 0
            isStreamingEnabled = false
            mdsService = nil
            mdsDataExportCharacteristic = nil
            serviceDiscoveryRetryCount = 0
        case .connecting:
            updateChunksLabel(with: "Connecting...")
        case .connected:
            updateChunksLabel(with: "Connected - initializing MDS")
            // Re-setup MDS when reconnected
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.setupMDSChunkForwarding()
            }
        default:
            break
        }
    }
    
    func bootloaderNameReceived(_ name: String) {
        bootloaderName.text = name
    }
    
    func bootloaderModeReceived(_ mode: BootloaderInfoResponse.Mode) {
        bootloaderMode.text = mode.description
    }
    
    func bootloaderSlotReceived(_ slot: UInt64) {
        bootloaderSlot.text = "\(slot)"
    }
    
    func appInfoReceived(_ output: String) {
        kernel.text = output
    }
    
    func mcuMgrParamsReceived(buffers: Int, size: Int) {
        mcuMgrParams.text = "\(buffers) x \(size) bytes"
    }
}
