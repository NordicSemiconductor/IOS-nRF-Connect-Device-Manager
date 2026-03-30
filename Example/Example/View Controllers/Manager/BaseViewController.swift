/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import CoreBluetooth
import iOSMcuManagerLibrary
import iOSOtaLibrary

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
    
    weak var deviceStatusDelegate: DeviceStatusManager.Delegate? {
        didSet {
            if let peripheralState {
                deviceStatusDelegate?.connectionStateDidChange(peripheralState)
            }
            if let statusInfo {
                deviceStatusDelegate?.statusInfoDidChange(statusInfo)
            }
            if let otaStatus {
                deviceStatusDelegate?.otaStatusChanged(otaStatus)
            }
            if let observabilityStatusInfo {
                deviceStatusDelegate?.observabilityStatusChanged(observabilityStatusInfo)
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
    
    private var deviceStatusManager: DeviceStatusManager?
    
    private var observabilityTask: Task<Void, Never>?
    private var observabilityIdentifier: UUID?
    private var observabilityManager: ObservabilityManager?
    
    private var deviceInfoRequested: Bool = false
    private var statusInfoCallback: (() -> ())?
    
    private var peripheralState: PeripheralState? {
        didSet {
            guard let peripheralState else { return }
            deviceStatusDelegate?.connectionStateDidChange(peripheralState)
        }
    }
    
    private var statusInfo: DeviceStatusInfo? {
        didSet {
            guard let statusInfo else { return }
            deviceStatusDelegate?.statusInfoDidChange(statusInfo)
        }
    }
    
    private var otaStatus: OTAStatus? {
        didSet {
            guard let otaStatus else { return }
            deviceStatusDelegate?.otaStatusChanged(otaStatus)
        }
    }
    
    private var observabilityStatusInfo: ObservabilityStatusInfo?
    
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
        disconnect()
    }
    
    // MARK: disconnect()
    
    func disconnect() {
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
        
        if deviceStatusManager == nil {
            deviceStatusManager = DeviceStatusManager(
                transport, logDelegate: UIApplication.shared.delegate as? McuMgrLogDelegate
            )
        }
        guard let deviceStatusManager else { return }
        
        Task { @MainActor in
            statusInfo = await deviceStatusManager.requestStatusInfo()
            
            guard let peripheral = peripheral?.basePeripheral else {
                onDeviceStatusFinished()
                return
            }
            otaStatus = await deviceStatusManager.requestOTAStatus(for: peripheral.identifier)
            onDeviceStatusFinished()
        }
    }
    
    // MARK: onDeviceStatusFinished
    
    private func onDeviceStatusFinished() {
        guard let statusInfoCallback else { return }
        statusInfoCallback()
        deviceInfoRequested = true
        self.statusInfoCallback = nil
    }
}
 
// MARK: - Observability

extension BaseViewController {
        
    func observabilityButtonTapped() {
        guard let observabilityIdentifier else {
            onDeviceStatusReady {} // Full Reconnection
            return
        }
        
        switch observabilityStatusInfo?.status {
        case .receivedEvent(let event):
            switch event {
            case .online(false):
                do {
                    try observabilityManager?.continuePendingUploads(for: observabilityIdentifier)
                } catch {
                    print("RETRY Error: \(error.localizedDescription)")
                }
            default:
                disconnect()
            }
        default:
            disconnect()
        }
    }
    
    private func launchObservabilityTask() {
        observabilityTask = Task { @MainActor [unowned self] in
            let manager: ObservabilityManager! = observabilityManager
            let observabilityIdentifier: UUID! = observabilityIdentifier
            let observabilityStream = manager.connectToDevice(observabilityIdentifier)
            do {
                for try await event in observabilityStream {
                    processObservabilityEvent(event.event)
                }
                print("STOPPED Listening to \(observabilityIdentifier.uuidString) Connection Events.")
                observabilityStatusInfo?.updatedStatus(.connectionClosed)
                if let observabilityStatusInfo {
                    deviceStatusDelegate?.observabilityStatusChanged(observabilityStatusInfo)
                }
            } catch let obsError as ObservabilityError {
                print("CAUGHT ObservabilityManagerError \(obsError.localizedDescription)")
                switch obsError {
                case .mdsServiceNotFound:
                    observabilityStatusInfo?.updatedStatus(.unsupported(obsError))
                case .pairingError:
                    observabilityStatusInfo?.updatedStatus(.pairingError)
                default:
                    observabilityStatusInfo?.updatedStatus(.errorEvent(obsError))
                }
                stopObservabilityManagerAndTask()
            } catch let error {
                print("CAUGHT Error \(error.localizedDescription) Listening to \(observabilityIdentifier.uuidString) Connection Events.")
                observabilityStatusInfo?.updatedStatus(.errorEvent(error))
                stopObservabilityManagerAndTask()
            }
        }
    }
    
    // MARK: processObservabilityEvent
    
    private func processObservabilityEvent(_ observabilityEvent: ObservabilityDeviceEvent) {
        switch observabilityEvent {
        case .connected:
            // Reset since on Observability Connection we'll get a report of pending chunks.
            observabilityStatusInfo = ObservabilityStatusInfo(status: .receivedEvent(.connected))
        case .updatedChunk(let chunk):
            observabilityStatusInfo?.processChunk(chunk)
            fallthrough // updateStatus as well
        default:
            observabilityStatusInfo?.updatedStatus(.receivedEvent(observabilityEvent))
        }
        
        guard let observabilityStatusInfo else { return }
        deviceStatusDelegate?.observabilityStatusChanged(observabilityStatusInfo)
    }
    
    private func stopObservabilityManagerAndTask() {
        defer {
            if let observabilityStatusInfo {
                deviceStatusDelegate?.observabilityStatusChanged(observabilityStatusInfo)
            }
        }
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
    }
}

// MARK: - PeripheralDelegate

extension BaseViewController: PeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        peripheralState = state
        switch state {
        case .connected:
            observabilityManager = ObservabilityManager()
            observabilityIdentifier = peripheral.identifier
            launchObservabilityTask()
        case .disconnecting, .disconnected:
            // Set to false, because a DFU update might change things if that's what happened.
            deviceInfoRequested = false
            stopObservabilityManagerAndTask()
        default:
            // Nothing to do here.
            break
        }
    }
}
