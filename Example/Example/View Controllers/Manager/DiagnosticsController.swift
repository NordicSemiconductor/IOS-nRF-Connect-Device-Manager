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
    @IBOutlet weak var otaStatus: UILabel!
    @IBOutlet weak var observabilityStatus: UILabel!
    
    @IBOutlet weak var observabilitySectionStatusLabel: UILabel!
    @IBOutlet weak var observabilitySectionStatusActivityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var observabilitySectionStatusPendingLabel: UILabel!
    @IBOutlet weak var observabilitySectionStatusUploadedLabel: UILabel!
    @IBOutlet weak var observabilityButton: UIButton!
    
    // MARK: @IBAction(s)
    
    @IBAction func refreshTapped(_ sender: UIButton) {
        guard let baseViewController = parent as? BaseViewController else { return }
        baseViewController.onDeviceStatusReady { [unowned self] in
            statsManager.list(callback: statsCallback)
        }
    }
    
    @IBAction func observabilityTapped(_ sender: UIButton) {
        guard let baseViewController = parent as? BaseViewController else { return }
        baseViewController.observabilityButtonTapped()
    }
    
    @IBAction func observabilityLearnMoreTapped(_ sender: UIButton) {
        guard let baseViewController = parent as? BaseViewController else { return }
        let alertController = UIAlertController(title: "Help", message: nil, preferredStyle: .alert)
        alertController.message = """
        
        nRF Cloud Observability is a comprehensive suite of monitoring, diagnostics, and actionable insights for embedded devices. It allows developers and engineering teams to track, analyze, and act on device behavior and reliability in real time.
            
        nRF Connect Device Manager forwards Chunks payload obtained from embedded devices with Monitoring & Diagnostics Service (MDS) to nRF Cloud Services for analysis.
        """
        if let url = URL(string: "https://docs.nordicsemi.com/bundle/nrf-cloud/page/index.html/") {
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
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        (parent as? BaseViewController)?.onDeviceStatusAccessoryTapped(at: indexPath)
    }
}

// MARK: - Private

private extension DiagnosticsController {
    
    func showObservabilityActivityIndicator(_ isVisible: Bool) {
        observabilitySectionStatusActivityIndicator.hidesWhenStopped = true
        if isVisible {
            observabilitySectionStatusActivityIndicator.isHidden = false
            if !observabilitySectionStatusActivityIndicator.isAnimating {
                observabilitySectionStatusActivityIndicator.startAnimating()
            }
        } else {
            observabilitySectionStatusActivityIndicator.stopAnimating()
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

extension DiagnosticsController: DeviceStatusManager.Delegate {
    
    func connectionStateDidChange(_ state: PeripheralState) {
        connectionStatus.text = state.description
    }
    
    func statusInfoDidChange(_ info: DeviceStatusInfo) {
        if let buffers = info.bufferCount, let size = info.bufferSize {
            mcuMgrParams.text = "\(buffers) x \(size) bytes"
        }
        if let appInfo = info.appInfoOutput {
            kernel.text = appInfo
        }
        bootloaderName.text = (info.bootloader ?? .unknown).description
        if let mode = info.bootloaderMode {
            bootloaderMode.text = mode.description
        }
        if let slot = info.bootloaderSlot {
            bootloaderSlot.text = "\(slot)"
        }
    }
    
    func otaStatusChanged(_ status: OTAStatus) {
        otaStatus.text = status.description
    }
    
    func observabilityStatusChanged(_ statusInfo: ObservabilityStatusInfo) {
        observabilityStatus.text = statusInfo.status.description
        switch statusInfo.status {
        case .receivedEvent(let event):
            switch event {
            case .connected:
                observabilitySectionStatusLabel.text = "Status: Connected over BLE"
                observabilitySectionStatusLabel.textColor = .systemYellow
                observabilityButton.setTitle("Disconnect", for: .normal)
                showObservabilityActivityIndicator(false)
            case .disconnected:
                observabilitySectionStatusLabel.text = "Status: Offline"
                observabilitySectionStatusLabel.textColor = .secondaryLabel
                observabilityButton.setTitle("Connect", for: .normal)
                showObservabilityActivityIndicator(false)
            case .notifications:
                observabilitySectionStatusLabel.text = "Status: Notifications Enabled"
                observabilitySectionStatusLabel.textColor = .systemYellow
            case .authenticated:
                observabilitySectionStatusLabel.text = "Status: Authenticated"
                observabilitySectionStatusLabel.textColor = .systemYellow
            case .online(let isTrue):
                if isTrue {
                    observabilitySectionStatusLabel.text = "Status: Online"
                    observabilitySectionStatusLabel.textColor = .systemGreen
                } else {
                    observabilitySectionStatusLabel.text = "Status: Network Unavailable"
                    observabilitySectionStatusLabel.textColor = .systemYellow
                    observabilityButton.setTitle("Retry Network", for: .normal)
                }
                showObservabilityActivityIndicator(true)
            case .updatedChunk(let chunk):
                switch chunk.status {
                case .pendingUpload:
                    observabilitySectionStatusLabel.text = "Status: Pending Upload"
                    observabilitySectionStatusLabel.textColor = .systemYellow
                case .uploading:
                    observabilitySectionStatusLabel.text = "Status: Uploading"
                    observabilityButton.setTitle("Disconnect", for: .normal)
                case .success:
                    observabilitySectionStatusLabel.text = "Status: Awaiting New Chunks"
                    observabilitySectionStatusLabel.textColor = .systemGreen
                    observabilityButton.setTitle("Disconnect", for: .normal)
                case .uploadError:
                    // Should be handled by .errorEvent
                    break
                }
                
                showObservabilityActivityIndicator(true)
                observabilitySectionStatusPendingLabel.text = statusInfo.pendingBytesString()
                observabilitySectionStatusUploadedLabel.text = statusInfo.uploadedBytesString()
            }
        case .connectionClosed:
            showObservabilityActivityIndicator(false)
            
            observabilitySectionStatusLabel.text = "Status: Offline"
            observabilitySectionStatusLabel.textColor = .secondaryLabel
            observabilityButton.setTitle("Connect", for: .normal)
        case .unsupported:
            showObservabilityActivityIndicator(false)
            
            observabilitySectionStatusLabel.text = "Status: Unsupported"
            observabilitySectionStatusLabel.textColor = .secondaryLabel
            observabilityButton.setTitle("Connect", for: .normal)
        case .errorEvent(let error):
            showObservabilityActivityIndicator(false)
            
            observabilitySectionStatusLabel.text = "Status: \(error.localizedDescription)"
            observabilitySectionStatusLabel.textColor = .systemRed
            observabilityButton.setTitle("Reconnect", for: .normal)
        case .pairingError:
            observabilitySectionStatusLabel.text = "Status: Pairing Error"
            observabilitySectionStatusLabel.textColor = .systemRed
            observabilityButton.setTitle("Reconnect", for: .normal)
        }
    }
}
