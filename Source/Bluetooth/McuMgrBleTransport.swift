/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

// MARK: - PeripheralState

public enum PeripheralState {
    /// State set when the manager starts connecting with the
    /// peripheral.
    case connecting
    /// State set when the peripheral gets connected and the
    /// manager starts service discovery.
    case initializing
    /// State set when device becones ready, that is all required
    /// services have been discovered and notifications enabled.
    case connected
    /// State set when close() method has been called.
    case disconnecting
    /// State set when the connection to the peripheral has closed.
    case disconnected
}

// MARK: - PeripheralDelegate

public protocol PeripheralDelegate: AnyObject {
    /// Callback called whenever peripheral state changes.
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState)
}

// MARK: - McuMgrBleTransport

public class McuMgrBleTransport: NSObject {
    
    /// The CBPeripheral for this transport to communicate with.
    private var peripheral: CBPeripheral?
    /// The CBCentralManager instance from which the peripheral was obtained.
    /// This is used to connect and cancel connection.
    private let centralManager: CBCentralManager
    /// The queue used to buffer reqeusts when another one is in progress.
    private let operationQueue: OperationQueue
    /// Lock used to wait for callbacks before continuing the request. This lock
    /// is used to wait for the device to setup (i.e. connection, descriptor)
    /// and the device to be received.
    private let connectionLock: ResultLock
    /// Lock used to wait for callbacks before continuing write requests.
    private var writeLocks: [UInt8: ResultLock]
    
    /// SMP Characteristic object. Used to write requests and receive
    /// notificaitons.
    private var smpCharacteristic: CBCharacteristic?
    
    /// Used to store fragmented response data.
    private var responseData: Data?
    private var responseLength: Int?
    /// An array of observers.
    private var observers: [ConnectionObserver]
    /// BLE transport delegate.
    public weak var delegate: PeripheralDelegate? {
        didSet {
            DispatchQueue.main.async {
                self.notifyPeripheralDelegate()
            }
        }
    }
    /// The log delegate will receive transport logs.
    public weak var logDelegate: McuMgrLogDelegate?
    
    public private(set) var state: PeripheralState = .disconnected {
        didSet {
            DispatchQueue.main.async {
                self.notifyPeripheralDelegate()
            }
        }
    }

    /// Creates a BLE transport object for the given peripheral.
    /// The implementation will create internal instance of
    /// CBCentralManager, and will retrieve the CBPeripheral from it.
    /// The target given as a parameter will not be used.
    /// The CBCentralManager from which the target was obtained will not
    /// be notified about connection states.
    ///
    /// The peripheral will connect automatically if a request to it is
    /// made. To disconnect from the peripheral, call `close()`.
    ///
    /// - parameter target: The BLE peripheral with Simple Managerment
    ///   Protocol (SMP) service.
    public convenience init(_ target: CBPeripheral) {
        self.init(target.identifier)
    }

    /// Creates a BLE transport object for the peripheral matching given
    /// identifier. The implementation will create internal instance of
    /// CBCentralManager, and will retrieve the CBPeripheral from it.
    /// The target given as a parameter will not be used.
    /// The CBCentralManager from which the target was obtained will not
    /// be notified about connection states.
    ///
    /// The peripheral will connect automatically if a request to it is
    /// made. To disconnect from the peripheral, call `close()`.
    ///
    /// - parameter targetIdentifier: The UUID of the peripheral with Simple Managerment
    ///   Protocol (SMP) service.
    public init(_ targetIdentifier: UUID) {
        self.centralManager = CBCentralManager(delegate: nil, queue: nil)
        self.identifier = targetIdentifier
        self.connectionLock = ResultLock(isOpen: false)
        self.writeLocks = [UInt8: ResultLock]()
        self.observers = []
        self.operationQueue = OperationQueue()
        self.operationQueue.maxConcurrentOperationCount = 1
        super.init()
        self.centralManager.delegate = self
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [targetIdentifier]).first {
            self.peripheral = peripheral
        }
    }
    
    public var name: String? {
        return peripheral?.name
    }
    
    public private(set) var identifier: UUID

    private func notifyPeripheralDelegate() {
        if let peripheral = self.peripheral {
            delegate?.peripheral(peripheral, didChangeStateTo: state)
        }
    }
}

// MARK: - McuMgrTransport

extension McuMgrBleTransport: McuMgrTransport {
    
    public func getScheme() -> McuMgrScheme {
        return .ble
    }
    
    public func send<T: McuMgrResponse>(data: Data, callback: @escaping McuMgrCallback<T>) {
        operationQueue.addOperation {
            for i in 0..<McuMgrBleTransportConstant.MAX_RETRIES {
                switch self._send(data: data) {
                case .failure(McuMgrTransportError.waitAndRetry):
                    sleep(UInt32(McuMgrBleTransportConstant.WAIT_AND_RETRY_INTERVAL))
                    self.log(msg: "Retry \(i)", atLevel: .info)
                    break
                case .failure(let error):
                    self.log(msg: error.localizedDescription, atLevel: .error)
                    DispatchQueue.main.async {
                        callback(nil, error)
                    }
                    return
                case .success(let responseData):
                    do {
                        let response: T = try McuMgrResponse.buildResponse(scheme: .ble, data: responseData)
                        DispatchQueue.main.async {
                            callback(response, nil)
                        }
                    } catch {
                        self.log(msg: error.localizedDescription, atLevel: .error)
                        DispatchQueue.main.async {
                            callback(nil, error)
                        }
                    }
                    return
                }
            }
        }
    }
    
    public func connect(_ callback: @escaping ConnectionCallback) {
        callback(.deferred)
    }
    
    public func close() {
        if let peripheral = peripheral, peripheral.state == .connected || peripheral.state == .connecting {
            log(msg: "Cancelling connection...", atLevel: .verbose)
            state = .disconnecting
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    public func addObserver(_ observer: ConnectionObserver) {
        observers.append(observer)
    }
    
    public func removeObserver(_ observer: ConnectionObserver) {
        if let index = observers.firstIndex(where: {$0 === observer}) {
            observers.remove(at: index)
        }
    }
    
    private func notifyStateChanged(_ state: McuMgrTransportState) {
        // The list of observers may be modified by each observer.
        // Better iterate a copy of it.
        let array = [ConnectionObserver](observers)
        for observer in array {
            observer.transport(self, didChangeStateTo: state)
        }
    }
    
    /// This method sends the data to the target. Before, it ensures that
    /// CBCentralManager is ready and the peripheral is connected.
    /// The peripheral will automatically be connected when it's not.
    ///
    /// - returns: A `Result` containing the full response `Data` if successful, `Error` if not. Note that if `McuMgrTransportError.waitAndRetry` is returned, said operation needs to be done externally to this call.
    private func _send(data: Data) -> Result<Data, Error> {
        if centralManager.state == .poweredOff || centralManager.state == .unsupported {
            return .failure(McuMgrBleTransportError.centralManagerPoweredOff)
        }

        // We might not have a peripheral instance yet, if the Central Manager has not
        // reported that it is powered on.
        // Wait until it is ready, and timeout if we do not get a valid peripheral instance
        let targetPeripheral: CBPeripheral

        if let existing = peripheral, centralManager.state == .poweredOn {
            targetPeripheral = existing
        } else {
            connectionLock.close(key: McuMgrBleTransportKey.awaitingCentralManager.rawValue)
            
            // Wait for the setup process to complete.
            let result = connectionLock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransportConstant.CONNECTION_TIMEOUT))
            resetConnectionLock()
            
            // Check for timeout, failure, or success.
            switch result {
            case .timeout:
                return .failure(McuMgrTransportError.connectionTimeout)
            case let .error(error):
                return .failure(error)
            case .success:
                guard let target = self.peripheral else {
                    return .failure(McuMgrTransportError.connectionTimeout)
                }
                // continue
                log(msg: "Central Manager  ready", atLevel: .verbose)
                targetPeripheral = target
            }
        }
        
        // Wait until the peripheral is ready.
        if smpCharacteristic == nil {
            // Close the lock.
            connectionLock.close(key: McuMgrBleTransportKey.discoveringSmpCharacteristic.rawValue)
            
            switch targetPeripheral.state {
            case .connected:
                // If the peripheral was already connected, but the SMP
                // characteristic has not been set, start by performing service
                // discovery. Once the characteristic's notification is enabled,
                // the semaphore will be signalled and the request can be sent.
                log(msg: "Peripheral already connected", atLevel: .info)
                log(msg: "Discovering services...", atLevel: .verbose)
                state = .connecting
                targetPeripheral.delegate = self
                targetPeripheral.discoverServices([McuMgrBleTransportConstant.SMP_SERVICE])
            case .disconnected:
                // If the peripheral is disconnected, begin the setup process by
                // connecting to the device. Once the characteristic's
                // notification is enabled, the semaphore will be signalled and
                // the request can be sent.
                log(msg: "Connecting...", atLevel: .verbose)
                state = .connecting
                centralManager.connect(targetPeripheral)
            case .connecting:
                log(msg: "Device is connecting. Wait...", atLevel: .info)
                state = .connecting
                // Do nothing. It will switch to .connected or .disconnected.
            case .disconnecting:
                log(msg: "Device is disconnecting. Wait...", atLevel: .info)
                // If the peripheral's connection state is transitioning, wait and retry
                return .failure(McuMgrTransportError.waitAndRetry)
            @unknown default:
                log(msg: "Unknown state", atLevel: .warning)
            }
            
            // Wait for the setup process to complete.
            let result = connectionLock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransportConstant.CONNECTION_TIMEOUT))
            resetConnectionLock()
            
            // Check for timeout, failure, or success.
            switch result {
            case .timeout:
                state = .disconnected
                return .failure(McuMgrTransportError.connectionTimeout)
            case let .error(error):
                state = .disconnected
                return .failure(error)
            case .success:
                log(msg: "Device ready", atLevel: .info)
                // Continue.
            }
        }
        
        // Make sure the SMP characteristic is not nil.
        guard let smpCharacteristic = smpCharacteristic else {
            return .failure(McuMgrBleTransportError.missingCharacteristic)
        }
        
        // Check that data length does not exceed the mtu.
        let mtu = targetPeripheral.maximumWriteValueLength(for: .withoutResponse)
        if data.count > mtu {
            return .failure(McuMgrTransportError.insufficientMtu(mtu: mtu))
        }
        
        guard let sequenceNumber = readSequenceNumber(from: data) else {
            return .failure(McuMgrTransportError.badHeader)
        }
        
        writeLocks[sequenceNumber] = ResultLock(isOpen: false)
        
        // Write the value to the characteristic.
        log(msg: "-> \(data.hexEncodedString(options: .prepend0x))", atLevel: .debug)
        targetPeripheral.writeValue(data, for: smpCharacteristic, type: .withoutResponse)

        // Wait for the didUpdateValueFor(characteristic:) to open the lock.
        let result = writeLocks[sequenceNumber]!.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransportConstant.TRANSACTION_TIMEOUT))
        defer {
            clearState(for: sequenceNumber)
        }
        
        switch result {
        case .timeout:
            return .failure(McuMgrTransportError.sendTimeout)
        case .error(let error):
            return .failure(error)
        case .success:
            log(msg: "<- \(responseData?.hexEncodedString(options: .prepend0x) ?? "0 bytes")",
                atLevel: .debug)
            return .success(responseData ?? Data())
        }
    }
    
    private func readSequenceNumber(from data: Data) -> UInt8? {
        guard data.count > McuMgrHeader.HEADER_LENGTH else { return nil }
        return data.read(offset: 6) as UInt8
    }
    
    private func resetConnectionLock() {
        connectionLock.close()
    }
    
    private func clearState(for sequenceNumber: UInt8) {
        writeLocks[sequenceNumber] = nil
        responseData = nil
        responseLength = nil
    }
    
    private func log(msg: String, atLevel level: McuMgrLogLevel) {
        logDelegate?.log(msg, ofCategory: .transport, atLevel: level)
    }
}

// MARK: - CBCentralManagerDelegate

extension McuMgrBleTransport: CBCentralManagerDelegate {
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let peripheral = centralManager
                .retrievePeripherals(withIdentifiers: [identifier])
                .first {
                self.peripheral = peripheral
                connectionLock.open(key: McuMgrBleTransportKey.awaitingCentralManager.rawValue)
            } else {
                connectionLock.open(McuMgrBleTransportError.centralManagerNotReady)
            }
        default:
            connectionLock.open(McuMgrBleTransportError.centralManagerNotReady)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.identifier == peripheral.identifier else {
            return
        }
        log(msg: "Peripheral connected", atLevel: .info)
        state = .initializing
        log(msg: "Discovering services...", atLevel: .verbose)
        peripheral.delegate = self
        peripheral.discoverServices([McuMgrBleTransportConstant.SMP_SERVICE])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.identifier == peripheral.identifier else {
            return
        }
        log(msg: "Peripheral disconnected", atLevel: .info)
        peripheral.delegate = nil
        smpCharacteristic = nil
        connectionLock.open(McuMgrTransportError.disconnected)
        state = .disconnected
        notifyStateChanged(.disconnected)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.identifier == peripheral.identifier else {
            return
        }
        log(msg: "Peripheral failed to connect", atLevel: .warning)
        connectionLock.open(McuMgrTransportError.connectionFailed)
    }
}

// MARK: - CBPeripheralDelegate Delegate

extension McuMgrBleTransport: CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Check for error.
        guard error == nil else {
            connectionLock.open(error)
            return
        }
        
        let s = peripheral.services?
            .map({ $0.uuid.uuidString })
            .joined(separator: ", ")
            ?? "none"
        log(msg: "Services discovered: \(s)", atLevel: .verbose)
        
        // Get peripheral's services.
        guard let services = peripheral.services else {
            connectionLock.open(McuMgrBleTransportError.missingService)
            return
        }
        // Find the service matching the SMP service UUID.
        for service in services {
            if service.uuid == McuMgrBleTransportConstant.SMP_SERVICE {
                log(msg: "Discovering characteristics...", atLevel: .verbose)
                peripheral.discoverCharacteristics([McuMgrBleTransportConstant.SMP_CHARACTERISTIC],
                                                   for: service)
                return
            }
        }
        connectionLock.open(McuMgrBleTransportError.missingService)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        // Check for error.
        guard error == nil else {
            connectionLock.open(error)
            return
        }
        
        let c = service.characteristics?
            .map({ $0.uuid.uuidString })
            .joined(separator: ", ")
            ?? "none"
        log(msg: "Characteristics discovered: \(c)", atLevel: .verbose)
        
        // Get service's characteristics.
        guard let characteristics = service.characteristics else {
            connectionLock.open(McuMgrBleTransportError.missingCharacteristic)
            return
        }
        // Find the characteristic matching the SMP characteristic UUID.
        for characteristic in characteristics {
            if characteristic.uuid == McuMgrBleTransportConstant.SMP_CHARACTERISTIC {
                // Set the characteristic notification if available.
                if characteristic.properties.contains(.notify) {
                    log(msg: "Enabling notifications...", atLevel: .verbose)
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    connectionLock.open(McuMgrBleTransportError.missingNotifyProperty)
                }
                return
            }
        }
        connectionLock.open(McuMgrBleTransportError.missingCharacteristic)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard characteristic.uuid == McuMgrBleTransportConstant.SMP_CHARACTERISTIC else {
            return
        }
        // Check for error.
        guard error == nil else {
            connectionLock.open(error)
            return
        }
        
        log(msg: "Notifications enabled", atLevel: .verbose)
        
        // Set the SMP characteristic.
        smpCharacteristic = characteristic
        state = .connected
        notifyStateChanged(.connected)
        
        // The SMP Service and characateristic have now been discovered and set
        // up. Signal the dispatch semaphore to continue to send the request.
        connectionLock.open(key: McuMgrBleTransportKey.discoveringSmpCharacteristic.rawValue)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard characteristic.uuid == McuMgrBleTransportConstant.SMP_CHARACTERISTIC else {
            return
        }
        // Check for error.
        guard error == nil else {
            writeLocks.values.forEach {
                $0.open(error)
            }
            return
        }
        guard let data = characteristic.value else {
            writeLocks.values.forEach {
                $0.open(McuMgrTransportError.badResponse)
            }
            return
        }
        
        guard let sequenceNumber = readSequenceNumber(from: data) else {
            writeLocks.values.forEach {
                $0.open(McuMgrTransportError.badHeader)
            }
            return
        }
        
        // Get the expected length from the response data.
        if responseData == nil {
            // If we do not have any current response data, this is the initial
            // packet in a potentially fragmented response. Get the expected
            // length of the full response and initialize the responseData with
            // the expected capacity.
            guard let len = McuMgrResponse.getExpectedLength(scheme: getScheme(), responseData: data) else {
                writeLocks[sequenceNumber]?.open(McuMgrTransportError.badResponse)
                return
            }
            responseData = Data(capacity: len)
            responseLength = len
        }
                
        // Append the response data.
        responseData!.append(data)
        
        // If we have recevied all the bytes, signal the waiting lock.
        if responseData!.count >= responseLength! {
            writeLocks[sequenceNumber]?.open()
        }
    }
}

// MARK: - McuMgrBleTransportConstant

public enum McuMgrBleTransportConstant {
    
    public static let SMP_SERVICE = CBUUID(string: "8D53DC1D-1DB7-4CD3-868B-8A527460AA84")
    public static let SMP_CHARACTERISTIC = CBUUID(string: "DA2E7828-FBCE-4E01-AE9E-261174997C48")
    
    /// Max number of retries until the transaction is failed.
    fileprivate static let MAX_RETRIES = 3
    /// The interval to wait before attempting a transaction again in seconds.
    fileprivate static let WAIT_AND_RETRY_INTERVAL = 10
    /// Connection timeout in seconds.
    fileprivate static let CONNECTION_TIMEOUT = 20
    /// Transaction timout in seconds.
    fileprivate static let TRANSACTION_TIMEOUT = 30
}

// MARK: - McuMgrBleTransportKey

fileprivate enum McuMgrBleTransportKey: ResultLockKey {
    case awaitingCentralManager = "McuMgrBleTransport.awaitingCentralManager"
    case discoveringSmpCharacteristic = "McuMgrBleTransport.discoveringSmpCharacteristic"
}

/// Errors specific to BLE transport.
public enum McuMgrBleTransportError: Error {
    case centralManagerPoweredOff
    case centralManagerNotReady
    case missingService
    case missingCharacteristic
    case missingNotifyProperty
}

extension McuMgrBleTransportError: LocalizedError {
    
    public var errorDescription: String? {
        switch self {
        case .centralManagerPoweredOff:
            return "Central Manager powered OFF."
        case .centralManagerNotReady:
            return "Central Manager not ready."
        case .missingService:
            return "SMP service not found."
        case .missingCharacteristic:
            return "SMP characteristic not found."
        case .missingNotifyProperty:
            return "SMP characteristic does not have notify property."
        }
    }
    
}
