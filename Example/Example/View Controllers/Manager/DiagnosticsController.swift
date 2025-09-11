/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

// MARK: - DiagnosticsController

final class DiagnosticsController: UITableViewController {
    
    // MARK: @IBOutlet(s)
    
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var mcuMgrParams: UILabel!
    @IBOutlet weak var bootloaderName: UILabel!
    @IBOutlet weak var bootloaderMode: UILabel!
    @IBOutlet weak var bootloaderSlot: UILabel!
    @IBOutlet weak var kernel: UILabel!
    @IBOutlet weak var stats: UILabel!
    @IBOutlet weak var refreshAction: UIButton!
    @IBOutlet weak var nRFCloudStatus: UILabel!
    @IBOutlet weak var observabilityStatus: UILabel!
    
    @IBOutlet weak var observabilitySectionStatusLabel: UILabel!
    @IBOutlet weak var observabilitySectionStatusActivityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var observabilitySectionStatusPendingLabel: UILabel!
    @IBOutlet weak var observabilitySectionStatusUploadedLabel: UILabel!
    
    // MARK: @IBAction(s)
    
    @IBAction func refreshTapped(_ sender: UIButton) {
        guard let baseViewController = parent as? BaseViewController else { return }
        baseViewController.onDeviceStatusReady { [unowned self] in
            statsManager.list(callback: statsCallback)
        }
    }
    
    @IBAction func observabilityLearnMoreTapped(_ sender: UIButton) {
        guard let baseViewController = parent as? BaseViewController else { return }
        let alertController = UIAlertController(title: "Help", message: nil, preferredStyle: .alert)
        alertController.message = """
        
        nRF Cloud Observability is a comprehensive suite of monitoring, diagnostics, and actionable insights for embedded devices. It allows developers and engineering teams to track, analyze, and act on device behavior and reliability in real time.
            
        nRF Connect Device Manager forwards Chunks payload obtained from embedded devices with Monitoring & Diagnostics Service (MDS) to nRF Cloud Services for analysis.
        """
        if let url = URL(string: "https://mflt.io/nrf-app-discover-cloud-services") {
            alertController.addAction(UIAlertAction(title: "Discover nRF Cloud", style: .default, handler: { _ in
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }))
        }
        baseViewController.present(alertController, addingCancelAction: true,
                                   cancelActionTitle: "OK")
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
    
    // MARK: UIViewController
    
    override func viewDidAppear(_ animated: Bool) {
        guard let baseController = parent as? BaseViewController else { return }
        baseController.deviceStatusDelegate = self
        
        let transport: McuMgrTransport! = baseController.transport
        statsManager = StatsManager(transport: transport)
        statsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        
        observabilitySectionStatusActivityIndicator.isHidden = true
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
}

// MARK: - Private

private extension DiagnosticsController {
    
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

extension DiagnosticsController: DeviceStatusDelegate {
    
    func connectionStateDidChange(_ state: PeripheralState) {
        connectionStatus.text = state.description
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
    
    func nRFCloudStatusChanged(_ status: nRFCloudStatus) {
        switch status {
        case .unavailable:
            nRFCloudStatus.text = "UNAVAILABLE"
        case .missingProjectKey:
            nRFCloudStatus.text = "MISSING PROJECT KEY"
        case .available:
            nRFCloudStatus.text = "READY"
        }
    }
    
    func observabilityStatusChanged(_ status: ObservabilityStatus, pendingCount: Int, pendingBytes: Int, uploadedCount: Int, uploadedBytes: Int) {
        switch status {
        case .receivedEvent(let event):
            switch event {
            case .connected:
                observabilityStatus.text = "CONNECTED"
                
                observabilitySectionStatusLabel.text = "Status: Connected over BLE"
                observabilitySectionStatusLabel.textColor = .systemYellow
                observabilitySectionStatusActivityIndicator.isHidden = true
            case .disconnected:
                observabilityStatus.text = "DISCONNECTED"
                
                observabilitySectionStatusLabel.text = "Status: Offline"
                observabilitySectionStatusLabel.textColor = .secondaryLabel
                observabilitySectionStatusActivityIndicator.isHidden = true
            case .notifications:
                observabilityStatus.text = "NOTIFYING"
                observabilitySectionStatusLabel.text = "Status: Notifications Enabled"
                observabilitySectionStatusLabel.textColor = .systemYellow
            case .authenticated:
                observabilityStatus.text = "AUTHENTICATED"
                observabilitySectionStatusLabel.text = "Status: Authenticated"
                observabilitySectionStatusLabel.textColor = .systemYellow
            case .streaming(let isTrue):
                observabilityStatus.text = isTrue ? "STREAMING" : "NOT STREAMING"
                if isTrue {
                    observabilitySectionStatusLabel.text = "Status: Online"
                    observabilitySectionStatusLabel.textColor = .systemGreen
                    
                    observabilitySectionStatusActivityIndicator.isHidden = false
                    observabilitySectionStatusActivityIndicator.startAnimating()
                } else {
                    observabilitySectionStatusLabel.text = "Status: Offline"
                    observabilitySectionStatusLabel.textColor = .secondaryLabel
                    
                    observabilitySectionStatusActivityIndicator.stopAnimating()
                    observabilitySectionStatusActivityIndicator.isHidden = true
                }
            case .updatedChunk(let chunk, let chunkStatus):
                observabilityStatus.text = "STREAMING"
                
                switch chunkStatus {
                case .receivedAndPendingUpload:
                    observabilitySectionStatusLabel.text = "Status: Pending Upload"
                    observabilitySectionStatusLabel.textColor = .systemYellow
                case .uploading:
                    observabilitySectionStatusLabel.text = "Status: Uploading"
                case .success:
                    observabilitySectionStatusLabel.text = "Status: Awaiting New Chunks"
                    observabilitySectionStatusLabel.textColor = .systemGreen
                case .errorUploading:
                    observabilitySectionStatusLabel.text = "Error Uploading Chunk \(chunk.sequenceNumber)"
                    observabilitySectionStatusLabel.textColor = .systemRed
                }
                
                observabilitySectionStatusActivityIndicator.isHidden = false
                if !observabilitySectionStatusActivityIndicator.isAnimating {
                    observabilitySectionStatusActivityIndicator.startAnimating()
                }
                observabilitySectionStatusPendingLabel.text = "Pending: \(pendingCount) chunk(s), \(pendingBytes) bytes"
                observabilitySectionStatusUploadedLabel.text = "Uploaded: \(uploadedCount) chunk(s), \(uploadedBytes) bytes"
            }
        case .connectionClosed:
            observabilityStatus.text = "CLOSED"
            observabilitySectionStatusActivityIndicator.isHidden = true
            
            observabilitySectionStatusLabel.text = "Status: Offline"
            observabilitySectionStatusLabel.textColor = .secondaryLabel
        case .unavailable:
            observabilityStatus.text = "UNAVAILABLE"
            observabilitySectionStatusActivityIndicator.isHidden = true
            
            observabilitySectionStatusLabel.text = "Status: Unavailable"
            observabilitySectionStatusLabel.textColor = .secondaryLabel
        case .errorEvent(let error):
            observabilityStatus.text = "ERROR"
            observabilitySectionStatusActivityIndicator.isHidden = true
            
            observabilitySectionStatusLabel.text = "Status: Error \(error.localizedDescription)"
            observabilitySectionStatusLabel.textColor = .systemRed
        }
    }
}
