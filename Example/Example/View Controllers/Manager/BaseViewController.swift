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
    func otaStatusChanged(_ status: OTAStatus)
    func observabilityStatusChanged(_ status: ObservabilityStatus, pendingCount: Int, pendingBytes: Int, uploadedCount: Int, uploadedBytes: Int)
}

// MARK: - DeviceStatusRow

enum DeviceStatusRow: Int, CustomStringConvertible {
    case connection
    case mcuMgrParameters
    case bootloaderName
    case bootloaderMode
    case bootloaderSlot
    case kernel
    case otaStatus
    case observabilityStatus
    
    var description: String {
        switch self {
        case .connection:
            return "Connection"
        case .mcuMgrParameters:
            return "MCU Manager Parameters / Buffer Details"
        case .bootloaderName:
            return "Bootloader Name"
        case .bootloaderMode:
            return "Bootloader Mode"
        case .bootloaderSlot:
            return "Bootlaoder Slot"
        case .kernel:
            return "Kernel"
        case .otaStatus:
            return "OTA"
        case .observabilityStatus:
            return "Observability"
        }
    }
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
                deviceStatusDelegate?.otaStatusChanged(otaStatus)
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
    private var deviceInfoManager: DeviceInfoManager?
    
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
    
    private var otaStatus: OTAStatus? {
        didSet {
            guard let otaStatus else { return }
            deviceStatusDelegate?.otaStatusChanged(otaStatus)
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
        guard let deviceInfoManager else { return }
        Task { @MainActor in
            var deviceInfo: DeviceInfoToken!
            do {
                deviceInfo = try await deviceInfoManager.getDeviceInfoToken()
                let projectKey = try await deviceInfoManager.getProjectKey()
                
                self.otaStatus = .supported(deviceInfo, projectKey)
                onDeviceStatusFinished()
            } catch let managerError as DeviceInfoManagerError {
                if deviceInfo != nil {
                    self.otaStatus = .missingProjectKey(deviceInfo, managerError)
                } else {
                    self.otaStatus = .unsupported(managerError)
                }
                onDeviceStatusFinished()
            } catch let error {
                self.otaStatus = .unsupported(error)
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
                stopObservabilityManagerAndTask()
            } catch let error {
                print("CAUGHT Error \(error.localizedDescription) Listening to \(observabilityIdentifier.uuidString) Connection Events.")
                if let cbError = error as? CBATTError, cbError.code == .insufficientEncryption {
                    observabilityStatus = .pairingError(cbError)
                } else {
                    observabilityStatus = .errorEvent(error)
                }
                stopObservabilityManagerAndTask()
            }
        }
    }
    
    // MARK: processObservabilityEvent
    
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
    
    private func stopObservabilityManagerAndTask() {
        guard let observabilityIdentifier else { return }
        print(#function)
        observabilityManager?.disconnect(from: observabilityIdentifier)
        observabilityManager = nil
        
        observabilityTask?.cancel()
        observabilityTask = nil
        self.observabilityIdentifier = nil
    }
}

// MARK: - onDeviceStatusAccessoryTapped

extension BaseViewController {
    
    func onDeviceStatusAccessoryTapped(at indexPath: IndexPath) {
        guard let statusRow = DeviceStatusRow(rawValue: indexPath.row) else { return }
        let helpDialogAlertController = UIAlertController(title: "\(statusRow) Help", message: nil, preferredStyle: .alert)
        switch statusRow {
        case .connection:
            helpDialogAlertController.message = "\nReports the status of the Bluetooth LE connection to the device."
        case .mcuMgrParameters:
            helpDialogAlertController.message = "\nNumber of MCU Manager buffers and their size. Requires MCU Mgr Parameters command in OS Group."
        case .bootloaderName:
            helpDialogAlertController.message = "\nName of the Bootloader. Requires Bootloader Info command in OS Group."
        case .bootloaderMode:
            helpDialogAlertController.message = "\nMode of the MCUboot Bootloader."
        case .bootloaderSlot:
            helpDialogAlertController.message = "\nAlso known as \"Active B0 Slot\"; slot from which nRF Secure Immutable Bootloader (NSIB), also known as B0, booted the Application."
        case .kernel:
            helpDialogAlertController.message = "\nKernel name and version. Requires Application Info command in OS Group."
        case .otaStatus:
            helpDialogAlertController.message = "\nReports whether Firmware Over-the-Air (OTA) Updates via nRF Cloud are supported in this device."
            if let url = URL(string: "https://docs.nordicsemi.com/bundle/nrf-cloud/page/Devices/FirmwareUpdate/FOTAOverview.html") {
                helpDialogAlertController.addAction(UIAlertAction(title: "OTA Documentation", style: .default, handler: { _ in
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }))
            }
        case .observabilityStatus:
            helpDialogAlertController.message = "\nReports whether nRF Cloud Observability is supported and active for this device. nRF Cloud Observability allows collecting and analysing on-device metrics such as coredumps and logs from devices in your fleet. Useful for debugging bugs & crashes."
            if let url = URL(string: "https://docs.nordicsemi.com/bundle/nrf-cloud/page/index.html") {
                helpDialogAlertController.addAction(UIAlertAction(title: "Discover nRF Cloud", style: .default, handler: { _ in
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }))
            }
        }
        present(helpDialogAlertController, addingCancelAction: true, cancelActionTitle: "OK")
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

// MARK: - onDFUStart

extension BaseViewController {
    
    func onDFUStart() {
        stopObservabilityManagerAndTask()
        otaManager = nil
    }
}

// MARK: - PeripheralDelegate

extension BaseViewController: PeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        peripheralState = state
        switch state {
        case .connected:
            otaManager = OTAManager()
            deviceInfoManager = DeviceInfoManager(peripheral.identifier)
            observabilityManager = ObservabilityManager()
            observabilityIdentifier = peripheral.identifier
            launchObservabilityTask()
        case .disconnecting, .disconnected:
            // Set to false, because a DFU update might change things if that's what happened.
            deviceInfoRequested = false
            otaManager = nil
            deviceInfoManager = nil
            stopObservabilityManagerAndTask()
        default:
            // Nothing to do here.
            break
        }
    }
}
