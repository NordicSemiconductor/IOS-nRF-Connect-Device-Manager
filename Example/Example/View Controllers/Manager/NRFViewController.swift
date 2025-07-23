/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary
import CoreBluetooth

class NRFViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, McuMgrViewController, DeviceStatusDelegate, FirmwareUpgradeDelegate {
    
    // MARK: - Properties
    
    private var tableView: UITableView!
    private var checkUpdateButton: UIButton!
    private var statusLabel: UILabel!
    private var updateInfoLabel: UILabel!
    private var installButton: UIButton!
    private var activityIndicator: UIActivityIndicatorView!
    private var footerView: UIView!
    
    // Table view cells
    private var connectionStatusLabel: UILabel!
    private var mdsServiceLabel: UILabel!
    private var smpServiceLabel: UILabel!
    private var mdsChunksLabel: UILabel!
    private var projectKeyTextField: UITextField!
    private var hardwareVersionTextField: UITextField!
    private var softwareTypeTextField: UITextField!
    private var disVersionLabel: UILabel!
    private var smpVersionLabel: UILabel!
    
    private var imageManager: ImageManager!
    private var memfaultOTAManager: MemfaultOTAManager?
    private var mdsManager: MemfaultManager!
    private var currentVersion: String? // DIS version
    private var smpVersion: String? // SMP version from image list
    private var updateInfo: MemfaultOTAManager.UpdateInfo?
    private var hasCheckedForUpdate: Bool = false
    private var hasMDSService: Bool = false
    private var hasSMPService: Bool = false
    private var hasCheckedCapabilities: Bool = false
    private var chunksReceived: Int = 0
    private var chunksForwarded: Int = 0
    private var isStreamingMDS: Bool = false
    private var firmwareUpgradeManager: FirmwareUpgradeManager?
    private var waitingForReconnectAfterUpdate: Bool = false
    
    var transport: McuMgrTransport! {
        didSet {
            if transport != nil {
                imageManager = ImageManager(transport: transport)
                imageManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            } else {
            }
        }
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupMDSManager()
        
        // Clear incorrect cached software type if it's a model number
        let defaults = UserDefaults.standard
        if let storedType = defaults.string(forKey: "memfault_software_type"),
           (storedType == "nrf5340" || storedType == "nrf52840" || storedType == "nrf53") {
            // These are model numbers, not software types - clear it
            defaults.removeObject(forKey: "memfault_software_type")
        }
        
        loadStoredProjectInfo()
        
        // Create and set up table view
        tableView = UITableView(frame: view.bounds, style: .grouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        view.addSubview(tableView)
        
        // Create UI elements
        checkUpdateButton = UIButton(type: .system)
        checkUpdateButton.setTitle("Check for Updates", for: .normal)
        checkUpdateButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        checkUpdateButton.backgroundColor = UIColor.nordicBlue
        checkUpdateButton.setTitleColor(.white, for: .normal)
        checkUpdateButton.layer.cornerRadius = 8
        checkUpdateButton.translatesAutoresizingMaskIntoConstraints = false
        checkUpdateButton.addTarget(self, action: #selector(checkForUpdates), for: .touchUpInside)
        checkUpdateButton.isEnabled = false
        
        statusLabel = UILabel()
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        
        updateInfoLabel = UILabel()
        updateInfoLabel.textAlignment = .center
        updateInfoLabel.numberOfLines = 0
        updateInfoLabel.font = .systemFont(ofSize: 14)
        updateInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        updateInfoLabel.isHidden = true
        
        installButton = UIButton(type: .system)
        installButton.setTitle("Install Update", for: .normal)
        installButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        installButton.backgroundColor = UIColor.nordicGreen
        installButton.setTitleColor(.white, for: .normal)
        installButton.layer.cornerRadius = 8
        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.addTarget(self, action: #selector(installUpdate), for: .touchUpInside)
        installButton.isHidden = true
        
        if #available(iOS 13.0, *) {
            activityIndicator = UIActivityIndicatorView(style: .medium)
        } else {
            activityIndicator = UIActivityIndicatorView(style: .gray)
        }
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        
        // Set initial footer
        updateTableFooter()
        
        fetchCurrentVersion()
    }
    
    private var hasInitialized = false
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let parent = parent?.parent as? BaseViewController {
            parent.deviceStatusDelegate = self
            
            // Initialize state
            if let state = parent.state, state == .connected && !hasInitialized {
                hasInitialized = true
                // Clear previous state
                hasMDSService = false
                hasSMPService = false
                hasCheckedCapabilities = false
                hasCheckedForUpdate = false
                
                // Small delay to allow MDS service discovery before detecting capabilities
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Force table reload to ensure consistent state
                    self.tableView.reloadData()
                    
                    // Detect device capabilities and fetch version
                    self.detectDeviceCapabilities()
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop MDS streaming when leaving the view
        if isStreamingMDS {
            stopMDSStreaming()
        }
        
        // Save any entered project info
        saveProjectInfo()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Table View Data Source
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // Device Info, MDS Status
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Device Info
            return 8 // Connection, SMP Service, SMP Version, MDS Service, Project Key, Hardware Version, Software Type, DIS Version
        case 1: // MDS Status
            return hasMDSService ? 1 : 0
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Device Information"
        case 1:
            return hasMDSService ? "Monitoring & Diagnostic Service" : nil
        default:
            return nil
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
        
        switch indexPath.section {
        case 0: // Device Info
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Connection"
                if connectionStatusLabel == nil {
                    connectionStatusLabel = UILabel()
                }
                connectionStatusLabel.text = state?.description ?? "Disconnected"
                cell.detailTextLabel?.text = connectionStatusLabel.text
            case 1:
                cell.textLabel?.text = "SMP Service"
                if smpServiceLabel == nil {
                    smpServiceLabel = UILabel()
                }
                smpServiceLabel.text = hasSMPService ? "Available" : "Not Available"
                smpServiceLabel.textColor = hasSMPService ? UIColor.nordicGreen : .systemRed
                cell.detailTextLabel?.text = smpServiceLabel.text
                cell.detailTextLabel?.textColor = smpServiceLabel.textColor
            case 2:
                cell.textLabel?.text = "Software Version (SMP)"
                if smpVersionLabel == nil {
                    smpVersionLabel = UILabel()
                }
                smpVersionLabel.text = smpVersion ?? "..."
                cell.detailTextLabel?.text = smpVersionLabel.text
            case 3:
                cell.textLabel?.text = "MDS Service"
                if mdsServiceLabel == nil {
                    mdsServiceLabel = UILabel()
                }
                mdsServiceLabel.text = hasMDSService ? "Available" : "Not Available"
                mdsServiceLabel.textColor = hasMDSService ? UIColor.nordicGreen : .systemRed
                cell.detailTextLabel?.text = mdsServiceLabel.text
                cell.detailTextLabel?.textColor = mdsServiceLabel.textColor
            case 4:
                cell.textLabel?.text = "Project Key"
                cell.selectionStyle = .none
                if projectKeyTextField == nil {
                    projectKeyTextField = UITextField()
                    projectKeyTextField.placeholder = "Enter Memfault Project Key"
                    projectKeyTextField.textAlignment = .right
                    projectKeyTextField.font = .systemFont(ofSize: 17)
                    projectKeyTextField.addTarget(self, action: #selector(projectInfoChanged), for: .editingChanged)
                    projectKeyTextField.text = UserDefaults.standard.string(forKey: "memfault_project_key")
                }
                projectKeyTextField.frame = CGRect(x: 0, y: 0, width: 200, height: 44)
                cell.accessoryView = projectKeyTextField
            case 5:
                cell.textLabel?.text = "Hardware Version"
                cell.selectionStyle = .none
                if hardwareVersionTextField == nil {
                    hardwareVersionTextField = UITextField()
                    hardwareVersionTextField.placeholder = "e.g., nrf52840dk"
                    hardwareVersionTextField.textAlignment = .right
                    hardwareVersionTextField.font = .systemFont(ofSize: 17)
                    hardwareVersionTextField.addTarget(self, action: #selector(projectInfoChanged), for: .editingChanged)
                    hardwareVersionTextField.text = UserDefaults.standard.string(forKey: "memfault_hardware_version") ?? "nrf52840dk"
                }
                hardwareVersionTextField.frame = CGRect(x: 0, y: 0, width: 150, height: 44)
                cell.accessoryView = hardwareVersionTextField
            case 6:
                cell.textLabel?.text = "Software Type"
                cell.selectionStyle = .none
                if softwareTypeTextField == nil {
                    softwareTypeTextField = UITextField()
                    softwareTypeTextField.placeholder = "e.g., main"
                    softwareTypeTextField.textAlignment = .right
                    softwareTypeTextField.font = .systemFont(ofSize: 17)
                    softwareTypeTextField.addTarget(self, action: #selector(projectInfoChanged), for: .editingChanged)
                    softwareTypeTextField.text = UserDefaults.standard.string(forKey: "memfault_software_type") ?? "main"
                }
                softwareTypeTextField.frame = CGRect(x: 0, y: 0, width: 150, height: 44)
                cell.accessoryView = softwareTypeTextField
            case 7:
                cell.textLabel?.text = "Software Version (DIS)"
                if disVersionLabel == nil {
                    disVersionLabel = UILabel()
                }
                disVersionLabel.text = currentVersion ?? "..."
                cell.detailTextLabel?.text = disVersionLabel.text
            default:
                break
            }
        case 1: // MDS Status
            cell.textLabel?.text = "Status"
            if mdsChunksLabel == nil {
                mdsChunksLabel = UILabel()
            }
            mdsChunksLabel.text = "Chunks - Received: \(chunksReceived), Forwarded: \(chunksForwarded)"
            cell.detailTextLabel?.text = mdsChunksLabel.text
        default:
            break
        }
        
        return cell
    }
    
    private var state: PeripheralState? {
        if let parent = parent?.parent as? BaseViewController {
            return parent.state
        }
        return nil
    }
    
    // MARK: - MDS Setup and Management
    
    private func setupMDSManager() {
        // Only create a new manager if one doesn't exist
        if mdsManager == nil {
            mdsManager = MemfaultManager()
        }
        
        // Set callbacks
        mdsManager.onDeviceConnected = { [weak self] device in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // MDS is already detected in detectDeviceCapabilities
                // Just reset counters and start streaming
                self.chunksReceived = 0
                self.chunksForwarded = 0
                
                // Auto-start streaming when MDS is available
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !self.isStreamingMDS {
                        print("NRFViewController: Starting MDS streaming")
                        self.startMDSStreaming()
                    } else {
                        print("NRFViewController: MDS streaming already active")
                    }
                }
            }
        }
        
        mdsManager.onChunkReceived = { [weak self] chunk in
            DispatchQueue.main.async {
                print("NRFViewController: Chunk received, total: \(self?.chunksReceived ?? 0) + 1")
                self?.chunksReceived += 1
                self?.updateChunksUI()
            }
        }
        
        mdsManager.onChunkUploaded = { [weak self] chunk in
            DispatchQueue.main.async {
                self?.chunksForwarded += 1
                self?.updateChunksUI()
            }
        }
        
        mdsManager.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.showError("MDS Error: \(error.localizedDescription)")
            }
        }
        
        mdsManager.onDeviceInfoUpdated = { [weak self] device in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Update text fields with DIS values
                if let hardwareVersion = device.hardwareRevision {
                    self.hardwareVersionTextField?.text = hardwareVersion
                }
                // Don't use model number for software type - it should remain as configured
                // The software revision is used for version display
                if let softwareRevision = device.firmwareRevision {
                    self.currentVersion = softwareRevision
                }
                // Update project key if available from MDS
                if let projectKey = device.projectKey, !projectKey.isEmpty {
                    self.projectKeyTextField?.text = projectKey
                }
                
                // Don't reload table rows here - just save the values
                // The table will show updated values when cells are recreated
            }
        }
        
        // Check if already connected
        if let parent = parent?.parent as? BaseViewController,
           let transport = transport as? McuMgrBleTransport,
           let peripheral = transport.connectedPeripheral,
           parent.state == .connected {
            mdsManager.connectToDevice(peripheral: peripheral, transport: transport)
        }
    }
    
    private func updateChunksUI() {
        // Update the MDS status cell directly without reloading
        if hasMDSService && tableView.numberOfRows(inSection: 1) > 0 {
            if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 1)) {
                cell.detailTextLabel?.text = "Chunks - Received: \(chunksReceived), Forwarded: \(chunksForwarded)"
            }
        }
    }
    
    
    private func startMDSStreaming() {
        guard hasMDSService else { return }
        
        isStreamingMDS = true
        mdsManager.startDataStreaming()
    }
    
    private func stopMDSStreaming() {
        guard hasMDSService else { return }
        
        isStreamingMDS = false
        mdsManager.stopDataStreaming()
    }
    
    // MARK: - Device Capabilities Detection
    
    private func detectDeviceCapabilities() {
        guard !hasCheckedCapabilities else {
            return
        }
        
        hasCheckedCapabilities = true
        
        // Check for MDS service
        if let transport = transport as? McuMgrBleTransport,
           let peripheral = transport.connectedPeripheral {
            let mdsAvailable = transport.mdsService != nil
            let smpAvailable = transport.hasSMPService
            
            // Update the flags
            hasMDSService = mdsAvailable
            hasSMPService = smpAvailable
            
            // Update button state
            checkUpdateButton.isEnabled = smpAvailable && !(projectKeyTextField?.text?.isEmpty ?? true)
            
            // Connect MDS if available (this will trigger its own callbacks)
            if mdsAvailable && mdsManager != nil {
                print("NRFViewController: Connecting MDS manager to device")
                mdsManager.connectToDevice(peripheral: peripheral, transport: transport)
            } else {
                print("NRFViewController: MDS not available or manager is nil. mdsAvailable: \(mdsAvailable), mdsManager: \(mdsManager != nil ? "exists" : "nil")")
            }
            
            // Update table view for initial capabilities
            tableView.reloadData()
        }
        
        // Fetch current version only once
        if !hasCheckedForUpdate {
            fetchCurrentVersion()
        }
    }
    
    private func updateUIForDeviceCapabilities() {
        // Just update the button state, don't reload table view
        checkUpdateButton.isEnabled = hasSMPService && !(projectKeyTextField?.text?.isEmpty ?? true)
    }
    
    // MARK: - Version Management
    
    private func fetchCurrentVersion(allowDISWait: Bool = false) {
        
        if allowDISWait {
            // Wait briefly to allow DIS discovery
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?._fetchCurrentVersionInternal()
            }
        } else {
            _fetchCurrentVersionInternal()
        }
    }
    
    private func _fetchCurrentVersionInternal() {
        currentVersion = nil
        smpVersion = nil
        // Don't reload here - will reload when version is fetched
        
        // Always fetch both versions
        fetchDISVersion()
        fetchVersionViaSMP()
    }
    
    private func fetchDISVersion() {
        // Try DIS if available
        if let transport = transport as? McuMgrBleTransport,
           let peripheral = transport.connectedPeripheral,
           let disService = transport.disService {
            
            // Look for software revision characteristic
            if let softwareRevChar = disService.characteristics?.first(where: { $0.uuid == CBUUID(string: "2A28") }) {
                // Check if the value is already cached
                if let value = softwareRevChar.value,
                   let version = String(data: value, encoding: .utf8),
                   !version.isEmpty {
                    self.currentVersion = version
                    // Update the DIS version cell if visible
                    if let cell = self.tableView.cellForRow(at: IndexPath(row: 7, section: 0)) {
                        cell.detailTextLabel?.text = version
                    }
                    self.checkForUpdateIfNeeded()
                } else {
                    // Read the value
                    peripheral.readValue(for: softwareRevChar)
                    
                    // Set up a notification observer for DIS updates
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(disValueUpdated(_:)),
                        name: .init("DISValueUpdated"),
                        object: nil
                    )
                }
            }
        }
    }
    
    @objc private func disValueUpdated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let characteristicUUID = userInfo["uuid"] as? String,
              characteristicUUID == "2A28",
              let value = userInfo["value"] as? Data,
              let version = String(data: value, encoding: .utf8),
              !version.isEmpty else { return }
        
        self.currentVersion = version
        
        // Update the DIS version cell if visible
        if let cell = self.tableView.cellForRow(at: IndexPath(row: 7, section: 0)) {
            cell.detailTextLabel?.text = version
        }
        
        // If we're waiting for reconnect after update, also reload the table to show new version
        if waitingForReconnectAfterUpdate {
            tableView.reloadRows(at: [IndexPath(row: 7, section: 0)], with: .none)
        }
        
        self.checkForUpdateIfNeeded()
        
        // Remove observer after receiving the value
        NotificationCenter.default.removeObserver(self, name: .init("DISValueUpdated"), object: nil)
    }
    
    private func fetchVersionViaSMP() {
        guard let imageManager = imageManager else {
            smpVersion = nil
            return
        }
        
        
        imageManager.list { [weak self] response, error in
            DispatchQueue.main.async {
                if error != nil {
                    self?.smpVersion = nil
                    return
                }
                
                if let images = response?.images, !images.isEmpty {
                    // Get the active image version
                    if let activeImage = images.first(where: { $0.active }) {
                        let version = activeImage.version
                        self?.smpVersion = version
                        // Update the SMP version cell if visible
                        if let cell = self?.tableView.cellForRow(at: IndexPath(row: 2, section: 0)) {
                            cell.detailTextLabel?.text = version
                        }
                        // If we're waiting for reconnect after update, also reload the table to show new version
                        if self?.waitingForReconnectAfterUpdate ?? false {
                            self?.tableView.reloadRows(at: [IndexPath(row: 2, section: 0)], with: .none)
                        }
                        // Also set currentVersion if DIS version is not available
                        if self?.currentVersion == nil {
                            self?.currentVersion = version
                        }
                        self?.checkForUpdateIfNeeded()
                    } else if let firstImage = images.first {
                        // Fallback to first image if no active image
                        let version = firstImage.version
                        self?.smpVersion = version
                        // Update the SMP version cell if visible
                        if let cell = self?.tableView.cellForRow(at: IndexPath(row: 2, section: 0)) {
                            cell.detailTextLabel?.text = version
                        }
                        // If we're waiting for reconnect after update, also reload the table to show new version
                        if self?.waitingForReconnectAfterUpdate ?? false {
                            self?.tableView.reloadRows(at: [IndexPath(row: 2, section: 0)], with: .none)
                        }
                        // Also set currentVersion if DIS version is not available
                        if self?.currentVersion == nil {
                            self?.currentVersion = version
                        }
                        self?.checkForUpdateIfNeeded()
                    }
                } else {
                    self?.smpVersion = nil
                }
            }
        }
    }
    
    // MARK: - Update Management
    
    @objc private func projectInfoChanged() {
        saveProjectInfo()
        checkUpdateButton.isEnabled = hasSMPService && !(projectKeyTextField?.text?.isEmpty ?? true)
    }
    
    private func loadStoredProjectInfo() {
        // These will be loaded when the cells are created
        // We'll read from defaults when creating the cells
    }
    
    private func saveProjectInfo() {
        let defaults = UserDefaults.standard
        defaults.set(projectKeyTextField?.text, forKey: "memfault_project_key")
        defaults.set(hardwareVersionTextField?.text, forKey: "memfault_hardware_version")
        defaults.set(softwareTypeTextField?.text, forKey: "memfault_software_type")
    }
    
    private func checkForUpdateIfNeeded() {
        // Only auto-check if we haven't checked yet and have all required info
        if !hasCheckedForUpdate && currentVersion != nil && !(projectKeyTextField?.text?.isEmpty ?? true) {
            // Auto-check for updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkForUpdates()
            }
        }
    }
    
    @objc private func checkForUpdates() {
        guard let projectKey = projectKeyTextField?.text, !projectKey.isEmpty else {
            showError("Please enter your Memfault Project Key")
            return
        }
        
        guard let currentVersion = currentVersion else {
            showError("Could not determine current version")
            return
        }
        
        hasCheckedForUpdate = true
        
        statusLabel.text = "Checking for updates..."
        statusLabel.textColor = UIColor.primary
        statusLabel.isHidden = false
        checkUpdateButton.isEnabled = false
        activityIndicator.startAnimating()
        
        let hardwareVersion = hardwareVersionTextField?.text ?? "nrf52840dk"
        let softwareType = softwareTypeTextField?.text ?? "main"
        
        memfaultOTAManager = MemfaultOTAManager(
            projectKey: projectKey,
            hardwareVersion: hardwareVersion,
            softwareType: softwareType
        )
        
        memfaultOTAManager?.checkForUpdate(currentVersion: currentVersion, completion: { [weak self] (result) in
            DispatchQueue.main.async {
                // Ensure all UI updates happen on main thread
                self?.activityIndicator.stopAnimating()
                self?.checkUpdateButton.isEnabled = true
                
                switch result {
            case .success(let updateInfo):
                if let update = updateInfo {
                    self?.updateInfo = update
                    self?.statusLabel.textColor = UIColor.nordicGreen
                    self?.statusLabel.text = "Update available!"
                    self?.updateInfoLabel.text = "New version: \(update.version)\n\(update.releaseNotes ?? "")"
                    self?.updateInfoLabel.isHidden = false
                    self?.installButton.isHidden = false
                    // Create and set a new footer view with update info
                    self?.updateTableFooter()
                } else {
                    self?.statusLabel.textColor = UIColor.nordicBlue
                    self?.statusLabel.text = "You're running the latest version"
                    self?.updateInfoLabel.isHidden = true
                    self?.installButton.isHidden = true
                }
                
            case .failure(let error):
                self?.statusLabel.textColor = UIColor.nordicRed
                switch error {
                case .invalidProjectKey:
                    self?.statusLabel.text = "Invalid or missing project key"
                case .networkError(let underlyingError):
                    self?.statusLabel.text = "Network error: \(underlyingError.localizedDescription)"
                case .invalidResponse(let details):
                    self?.statusLabel.text = details ?? "Invalid response from server"
                case .noUpdateAvailable:
                    self?.statusLabel.textColor = UIColor.nordicBlue
                    self?.statusLabel.text = "You're running the latest version"
                }
                self?.updateInfoLabel.isHidden = true
                self?.installButton.isHidden = true
            }
            }
        })
    }
    
    @objc private func installUpdate() {
        guard let updateInfo = updateInfo else { return }
        
        installButton.isEnabled = false
        statusLabel.text = "Downloading firmware..."
        statusLabel.textColor = UIColor.primary
        
        memfaultOTAManager?.downloadFirmware(from: updateInfo.downloadUrl, progress: { [weak self] progress in
            DispatchQueue.main.async {
                self?.statusLabel.text = String(format: "Downloading: %.0f%%", progress * 100)
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self?.statusLabel.text = "Download complete"
                    self?.startFirmwareUpgrade(with: data)
                    
                case .failure(let error):
                    self?.statusLabel.textColor = UIColor.nordicRed
                    self?.statusLabel.text = "Download failed: \(error.localizedDescription)"
                    self?.installButton.isEnabled = true
                }
            }
        })
    }
    
    private func startFirmwareUpgrade(with data: Data) {
        guard let transport = transport else {
            showError("Transport not available")
            return
        }
        
        do {
            let tempURL = try FirmwareFormatDetector.saveFirmwareToTemporaryFile(data)
            let package = try McuMgrPackage(from: tempURL)
            
            firmwareUpgradeManager = FirmwareUpgradeManager(transport: transport, delegate: self)
            firmwareUpgradeManager?.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            
            statusLabel.text = "Starting firmware upgrade..."
            statusLabel.textColor = UIColor.primary
            
            firmwareUpgradeManager?.start(package: package)
            
        } catch {
            statusLabel.textColor = UIColor.nordicRed
            statusLabel.text = "Failed to start upgrade: \(error.localizedDescription)"
            installButton.isEnabled = true
        }
    }
    
    private func updateTableFooter() {
        // Remove existing constraints first
        checkUpdateButton.removeFromSuperview()
        statusLabel.removeFromSuperview()
        activityIndicator.removeFromSuperview()
        updateInfoLabel.removeFromSuperview()
        installButton.removeFromSuperview()
        
        // Create new footer view with correct size
        let footerHeight: CGFloat = updateInfo != nil ? 200 : 120
        let footerContainer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: footerHeight))
        
        // Re-add check button
        footerContainer.addSubview(checkUpdateButton)
        footerContainer.addSubview(statusLabel)
        footerContainer.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            checkUpdateButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            checkUpdateButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            checkUpdateButton.topAnchor.constraint(equalTo: footerContainer.topAnchor, constant: 20),
            checkUpdateButton.heightAnchor.constraint(equalToConstant: 44),
            
            statusLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: checkUpdateButton.bottomAnchor, constant: 10),
            
            activityIndicator.centerXAnchor.constraint(equalTo: checkUpdateButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: checkUpdateButton.centerYAnchor)
        ])
        
        // Add update info and install button if update is available
        if updateInfo != nil {
            footerContainer.addSubview(updateInfoLabel)
            footerContainer.addSubview(installButton)
            
            NSLayoutConstraint.activate([
                updateInfoLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
                updateInfoLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
                updateInfoLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
                
                installButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
                installButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
                installButton.topAnchor.constraint(equalTo: updateInfoLabel.bottomAnchor, constant: 10),
                installButton.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
        
        tableView.tableFooterView = footerContainer
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - DeviceStatusDelegate
    
    func connectionStateDidChange(_ state: PeripheralState) {
        
        if state == .connected && !hasInitialized {
            hasInitialized = true
            // Clear previous state
            hasMDSService = false
            hasSMPService = false
            hasCheckedCapabilities = false
            hasCheckedForUpdate = false
            
            // Small delay to allow MDS service discovery before detecting capabilities
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Detect device capabilities and fetch version
                self.detectDeviceCapabilities()
            }
            
            // Delay version fetch to allow DIS to be discovered first
            fetchCurrentVersion(allowDISWait: true)
        } else if state == .connected && hasInitialized {
            // Check if we're reconnecting after a firmware update
            if waitingForReconnectAfterUpdate {
                waitingForReconnectAfterUpdate = false
                
                // Reset MDS state for the reconnected device
                if mdsManager != nil {
                    // Clear the connected device to force fresh discovery
                    mdsManager.disconnect()
                    // Reset our tracking variables
                    hasMDSService = false
                    chunksReceived = 0
                    chunksForwarded = 0
                    isStreamingMDS = false
                    updateChunksUI()
                    // Don't recreate the manager - just reset the state
                    // The existing manager will be reconnected when detectDeviceCapabilities is called
                }
                
                // Wait a bit for services to be discovered, then fetch new version
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.statusLabel.text = "Verifying update..."
                    self?.statusLabel.textColor = UIColor.primary
                    // Clear the version and force a fresh check
                    self?.currentVersion = nil
                    self?.smpVersion = nil
                    self?.hasCheckedCapabilities = false
                    
                    // Re-detect capabilities which will fetch the new version
                    self?.detectDeviceCapabilities()
                    self?.fetchCurrentVersion(allowDISWait: true)
                    
                    // After fetching versions, show success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        self?.checkUpdateButton.setTitle("Check for Updates", for: .normal)
                        self?.checkUpdateButton.isEnabled = true
                        self?.statusLabel.text = "Update confirmed!"
                        self?.statusLabel.textColor = UIColor.nordicGreen
                        
                        // Clear the waiting flag
                        self?.waitingForReconnectAfterUpdate = false
                        
                        // Hide the status after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            self?.statusLabel.isHidden = true
                            self?.updateTableFooter()
                        }
                    }
                }
            } else {
            }
        } else {
            // Reset state when disconnected
            if state == .disconnected {
                hasInitialized = false
                hasCheckedForUpdate = false
                hasMDSService = false
                hasSMPService = false
                hasCheckedCapabilities = false
                currentVersion = nil
                updateUIForDeviceCapabilities()
            }
        }
    }
    
    func bootloaderNameReceived(_ name: String) {
        // Not needed for this implementation
    }
    
    func bootloaderModeReceived(_ mode: BootloaderInfoResponse.Mode) {
        // Not needed for this implementation
    }
    
    func bootloaderSlotReceived(_ slot: UInt64) {
        // Not needed for this implementation
    }
    
    func appInfoReceived(_ output: String) {
        // Not needed for this implementation
    }
    
    func mcuMgrParamsReceived(buffers: Int, size: Int) {
        // Not needed for this implementation
    }
    
    // MARK: - FirmwareUpgradeDelegate
    
    func upgradeDidStart(controller: FirmwareUpgradeController) {
        // Not needed for this implementation
    }
    
    func upgradeDidComplete() {
        // Not needed for this implementation
    }
    
    func upgradeStateDidChange(from previousState: FirmwareUpgradeState, to newState: FirmwareUpgradeState) {
        DispatchQueue.main.async { [weak self] in
            switch newState {
            case .validate:
                self?.checkUpdateButton.setTitle("Validating...", for: .normal)
                self?.statusLabel.isHidden = true
            case .upload:
                self?.checkUpdateButton.setTitle("Uploading...", for: .normal)
                self?.statusLabel.isHidden = true
            case .test:
                self?.checkUpdateButton.setTitle("Testing...", for: .normal)
                self?.statusLabel.isHidden = true
            case .confirm:
                self?.checkUpdateButton.setTitle("Confirming...", for: .normal)
                self?.statusLabel.isHidden = true
            case .reset:
                self?.checkUpdateButton.setTitle("Restarting...", for: .normal)
                self?.statusLabel.text = "Device is restarting..."
                self?.statusLabel.textColor = UIColor.primary
                self?.statusLabel.isHidden = false
                // Mark that we're expecting a reconnection
                self?.waitingForReconnectAfterUpdate = true
            case .success:
                self?.checkUpdateButton.setTitle("Confirming update...", for: .normal)
                self?.checkUpdateButton.isEnabled = false
                self?.statusLabel.text = "Update installed. Confirming..."
                self?.statusLabel.textColor = UIColor.nordicBlue
                self?.statusLabel.isHidden = false
                self?.installButton.isHidden = true
                self?.updateInfoLabel.isHidden = true
                // Clear the update info
                self?.updateInfo = nil
                self?.hasCheckedForUpdate = false
                // Update footer
                self?.updateTableFooter()
                // Mark that we're waiting for reconnect to confirm the update
                self?.waitingForReconnectAfterUpdate = true
            case .none:
                self?.checkUpdateButton.setTitle("Check for Updates", for: .normal)
            default:
                break
            }
        }
    }
    
    func upgradeDidFail(inState state: FirmwareUpgradeState, with error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.checkUpdateButton.setTitle("Check for Updates", for: .normal)
            self?.statusLabel.text = "Update failed: \(error.localizedDescription)"
            self?.statusLabel.textColor = UIColor.nordicRed
            self?.statusLabel.isHidden = false
            self?.installButton.isEnabled = true
        }
    }
    
    func upgradeDidCancel(state: FirmwareUpgradeState) {
        DispatchQueue.main.async { [weak self] in
            self?.checkUpdateButton.setTitle("Check for Updates", for: .normal)
            self?.statusLabel.text = "Update cancelled"
            self?.statusLabel.textColor = .orange
            self?.statusLabel.isHidden = false
            self?.installButton.isEnabled = true
        }
    }
    
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        DispatchQueue.main.async { [weak self] in
            let progress = Float(bytesSent) / Float(imageSize)
            self?.checkUpdateButton.setTitle(String(format: "Uploading: %.0f%%", progress * 100), for: .normal)
        }
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}