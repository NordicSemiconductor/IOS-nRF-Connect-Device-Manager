/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import CoreBluetooth
import iOSMcuManagerLibrary
import iOSOtaLibrary

// MARK: - DeviceStatusDelegate

protocol DeviceStatusDelegate: AnyObject {
    
    func connectionStateDidChange(_ state: PeripheralState)
    func bootloaderNameReceived(_ name: String)
    func bootloaderModeReceived(_ mode: BootloaderInfoResponse.Mode)
    func bootloaderSlotReceived(_ slot: UInt64)
    func appInfoReceived(_ output: String)
    func mcuMgrParamsReceived(buffers: Int, size: Int)
    func nRFCloudStatusChanged(_ status: nRFCloudStatus)
    func observabilityStatusChanged(_ status: ObservabilityStatus, pendingCount: Int, pendingBytes: Int, uploadedCount: Int, uploadedBytes: Int)
}

// MARK: - nRFCloudStatus

enum nRFCloudStatus {
    case unavailable(_ error: Error?)
    case missingProjectKey(_ deviceInfo: DeviceInfoToken, _ error: Error)
    case available(_ deviceInfo: DeviceInfoToken, _ projectKey: ProjectKey)
}

// MARK: - ObservabilityStatus

enum ObservabilityStatus {
    case unsupported(_ error: Error?)
    case receivedEvent(_ event: ObservabilityDeviceEvent)
    case connectionClosed
    case errorEvent(_ error: Error)
}

// MARK: - BaseViewController

final class BaseViewController: UITabBarController {
    
    // MARK: Properties
    
    weak var deviceStatusDelegate: DeviceStatusDelegate? {
        didSet {
            if let peripheralState {
                deviceStatusDelegate?.connectionStateDidChange(peripheralState)
            }
            if let bootloader {
                deviceStatusDelegate?.bootloaderNameReceived(bootloader.description)
            }
            if let bootloaderMode {
                deviceStatusDelegate?.bootloaderModeReceived(bootloaderMode)
            }
            if let bootloaderSlot {
                deviceStatusDelegate?.bootloaderSlotReceived(bootloaderSlot)
            }
            if let appInfoOutput {
                deviceStatusDelegate?.appInfoReceived(appInfoOutput)
            }
            if let mcuMgrParams {
                deviceStatusDelegate?.mcuMgrParamsReceived(buffers: mcuMgrParams.buffers, size: mcuMgrParams.size)
            }
            if let otaStatus {
                deviceStatusDelegate?.nRFCloudStatusChanged(otaStatus)
            }
            if let observabilityStatus {
                deviceStatusDelegate?.observabilityStatusChanged(observabilityStatus, pendingCount: observabilityPendingChunks, pendingBytes: observabilityPendingBytes, uploadedCount: observabilityUploadedChunks, uploadedBytes: observabilityUploadedBytes)
            }
        }
    }
    
    /**
     Shared ``McuMgrTransport`` for subclasses to use.
     */
    var transport: McuMgrTransport!
    
    var peripheral: DiscoveredPeripheral! {
        didSet {
            let bleTransport = McuMgrBleTransport(peripheral.basePeripheral)
            bleTransport.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
            bleTransport.delegate = self
            transport = bleTransport
        }
    }
    
    // MARK: Private Properties
    
    private var otaManager: OTAManager?
    
    private var observabilityTask: Task<Void, Never>?
    private var observabilityIdentifier: UUID?
    private var observabilityManager: ObservabilityManager?
    private var observabilityPendingChunks: Int = 0
    private var observabilityPendingBytes: Int = 0
    private var observabilityUploadedBytes: Int = 0
    private var observabilityUploadedChunks: Int = 0
    
    private var deviceInfoRequested: Bool = false
    private var statusInfoCallback: (() -> ())?
    
    private var peripheralState: PeripheralState? {
        didSet {
            guard let peripheralState else { return }
            deviceStatusDelegate?.connectionStateDidChange(peripheralState)
        }
    }
    
    private var bootloader: BootloaderInfoResponse.Bootloader? {
        didSet {
            guard let bootloader else { return }
            deviceStatusDelegate?.bootloaderNameReceived(bootloader.description)
        }
    }
    
    private var bootloaderMode: BootloaderInfoResponse.Mode? {
        didSet {
            if let bootloaderMode {
                deviceStatusDelegate?.bootloaderModeReceived(bootloaderMode)
            }
        }
    }
    
    private var bootloaderSlot: UInt64? {
        didSet {
            guard let bootloaderSlot else { return }
            deviceStatusDelegate?.bootloaderSlotReceived(bootloaderSlot)
        }
    }
    
    private var appInfoOutput: String? {
        didSet {
            guard let appInfoOutput else { return }
            deviceStatusDelegate?.appInfoReceived(appInfoOutput)
        }
    }
    
    private var mcuMgrParams: (buffers: Int, size: Int)? {
        didSet {
            guard let mcuMgrParams else { return }
            deviceStatusDelegate?.mcuMgrParamsReceived(buffers: mcuMgrParams.buffers, size: mcuMgrParams.size)
        }
    }
    
    private var otaStatus: nRFCloudStatus? {
        didSet {
            guard let otaStatus else { return }
            deviceStatusDelegate?.nRFCloudStatusChanged(otaStatus)
        }
    }
    
    private var observabilityStatus: ObservabilityStatus? {
        didSet {
            guard let observabilityStatus else { return }
            deviceStatusDelegate?.observabilityStatusChanged(observabilityStatus, pendingCount: observabilityPendingChunks, pendingBytes: observabilityPendingBytes, uploadedCount: observabilityUploadedChunks, uploadedBytes: observabilityUploadedBytes)
        }
    }
    
    // MARK: viewDidLoad()
    
    override func viewDidLoad() {
        title = peripheral.advertisedName
        
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.dynamicColor(light: .systemBackground, dark: .secondarySystemBackground)
           
            tabBar.tintColor = .nordic
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        } else {
            tabBar.tintColor = .nordic
            tabBar.isTranslucent = false
        }
    }
    
    // MARK: viewWillDisappear()
    
    override func viewWillDisappear(_ animated: Bool) {
        if let observabilityIdentifier {
            observabilityManager?.disconnect(from: observabilityIdentifier)
            observabilityTask?.cancel()
            observabilityTask = nil
        }
        transport?.close()
    }
}

// MARK: Device Status

extension BaseViewController {
    
    func onDeviceStatusReady(_ callback: @escaping () -> Void) {
        statusInfoCallback = callback
        guard !deviceInfoRequested else {
            onDeviceStatusFinished()
            return
        }
        
        let defaultManager = DefaultManager(transport: transport)
        defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        defaultManager.params { [weak self] response, error in
            if let count = response?.bufferCount,
               let size = response?.bufferSize {
                self?.mcuMgrParams = (Int(count), Int(size))
            }
            
            self?.requestApplicationInfo(defaultManager)
        }
    }
    
    private func requestApplicationInfo(_ defaultManager: DefaultManager) {
        defaultManager.applicationInfo(format: [.kernelName, .kernelVersion]) { [weak self] response, error in
            self?.appInfoOutput = response?.response
            self?.requestBootloaderInfo(defaultManager)
        }
    }
    
    private func requestBootloaderInfo(_ defaultManager: DefaultManager) {
        defaultManager.bootloaderInfo(query: .name) { [weak self] response, error in
            self?.bootloader = response?.bootloader
            guard response?.bootloader == .mcuboot else {
                self?.requestOTAReleaseInfo()
                return
            }
            
            defaultManager.bootloaderInfo(query: .mode) { [weak self] response, error in
                self?.bootloaderMode = response?.mode
                
                defaultManager.bootloaderInfo(query: .slot) { [weak self] response, error in
                    self?.bootloaderSlot = response?.activeSlot
                    self?.requestOTAReleaseInfo()
                }
            }
        }
    }
    
    // MARK: OTA
    
    private func requestOTAReleaseInfo() {
        otaManager?.getDeviceInfoToken { [unowned self] result in
            switch result {
            case .success(let deviceInfo):
                print("Obtained Device Info \(deviceInfo)")
                otaManager?.getProjectKey() { [unowned self] result in
                    switch result {
                    case .success(let projectKey):
                        print("Obtained Project Key \(projectKey)")
                        self.otaStatus = .available(deviceInfo, projectKey)
                        onDeviceStatusFinished()
                    case .failure(let error):
                        self.otaStatus = .missingProjectKey(deviceInfo, error)
                        onDeviceStatusFinished()
                    }
                }
            case .failure(let error):
                self.otaStatus = .unavailable(error)
                onDeviceStatusFinished()
            }
        }
    }
    
    // MARK: onDeviceStatusFinished
    
    private func onDeviceStatusFinished() {
        guard let statusInfoCallback else { return }
        statusInfoCallback()
        deviceInfoRequested = true
        self.statusInfoCallback = nil
    }
    
    // MARK: Observability
    
    private func launchObservabilityTask() {
        observabilityTask = Task { @MainActor [unowned self] in
            let manager: ObservabilityManager! = observabilityManager
            let observabilityIdentifier: UUID! = observabilityIdentifier
            let observabilityStream = manager.connectToDevice(observabilityIdentifier)
            do {
                for try await event in observabilityStream {
                    processObservabilityEvent(event.event)
                    observabilityStatus = .receivedEvent(event.event)
                }
                print("STOPPED Listening to \(observabilityIdentifier.uuidString) Connection Events.")
                observabilityStatus = .connectionClosed
            } catch let obsError as ObservabilityManagerError {
                print("CAUGHT ObservabilityManagerError \(obsError.localizedDescription)")
                switch obsError {
                case .mdsServiceNotFound:
                    observabilityStatus = .unsupported(obsError)
                default:
                    observabilityStatus = .errorEvent(obsError)
                }
            } catch let error {
                print("CAUGHT Error \(error.localizedDescription) Listening to \(observabilityIdentifier.uuidString) Connection Events.")
                observabilityStatus = .errorEvent(error)
            }
        }
    }
    
    private func processObservabilityEvent(_ observabilityEvent: ObservabilityDeviceEvent) {
        switch observabilityEvent {
        case .updatedChunk(let chunk, let status):
            switch status {
            case .receivedAndPendingUpload:
                observabilityPendingBytes += chunk.data.count
                observabilityPendingChunks += 1
            case .success:
                observabilityPendingBytes -= chunk.data.count
                observabilityPendingChunks -= 1
                
                observabilityUploadedBytes += chunk.data.count
                observabilityUploadedChunks += 1
            default:
                break
            }
        default:
            break
        }
    }
}

// MARK: - Present Dialog

extension BaseViewController {
    
    func present(_ alertViewController: UIAlertController,
                 addingCancelAction addCancelAction: Bool = false,
                 cancelActionTitle: String = "Cancel") {
        if addCancelAction {
            alertViewController.addAction(UIAlertAction(title: cancelActionTitle, style: .cancel))
        }
        
        // If the device is an ipad set the popover presentation controller
        if let presenter = alertViewController.popoverPresentationController {
            presenter.sourceView = self.view
            presenter.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            presenter.permittedArrowDirections = []
        }
        present(alertViewController, animated: true)
    }
}

// MARK: - PeripheralDelegate

extension BaseViewController: PeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        peripheralState = state
        switch state {
        case .connected:
            otaManager = OTAManager(peripheral.identifier)
            observabilityManager = ObservabilityManager()
            observabilityIdentifier = peripheral.identifier
            launchObservabilityTask()
        case .disconnecting, .disconnected:
            // Set to false, because a DFU update might change things if that's what happened.
            deviceInfoRequested = false
            otaManager = nil
            observabilityIdentifier = nil
            observabilityManager = nil
            observabilityTask?.cancel()
            observabilityTask = nil
        default:
            // Nothing to do here.
            break
        }
    }
}
