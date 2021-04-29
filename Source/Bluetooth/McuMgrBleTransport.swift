/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

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

public protocol PeripheralDelegate: AnyObject {
    /// Callback called whenever peripheral state changes.
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState)
}

public class McuMgrBleTransport: NSObject {
    
    public static let SMP_SERVICE = CBUUID(string: "8D53DC1D-1DB7-4CD3-868B-8A527460AA84")
    public static let SMP_CHARACTERISTIC = CBUUID(string: "DA2E7828-FBCE-4E01-AE9E-261174997C48")
    
    /// Max number of retries until the transaction is failed.
    private static let MAX_RETRIES = 3
    /// Connection timeout in seconds.
    private static let CONNECTION_TIMEOUT = 20
    /// Transaction timout in seconds.
    private static let TRANSACTION_TIMEOUT = 30
    
    /// The CBPeripheral for this transport to communicate with.
    private var peripheral: CBPeripheral?
    /// The CBCentralManager instance from which the peripheral was obtained.
    /// This is used to connect and cancel connection.
    private let centralManager: CBCentralManager
    /// Dispatch queue for queuing requests.
    private let dispatchQueue: DispatchQueue
    /// The queue used to buffer reqeusts when another one is in progress.
    private let operationQueue: OperationQueue
    /// Lock used to wait for callbacks before continuing the request. This lock
    /// is used to wait for the device to setup (i.e. connection, descriptor
    /// writes) and the device to be received.
    private let lock: ResultLock
    
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
        self.dispatchQueue = DispatchQueue(label: "McuMgrBleTransport")
        self.lock = ResultLock(isOpen: false)
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

//******************************************************************************
// MARK: McuMgrTransport
//******************************************************************************

extension McuMgrBleTransport: McuMgrTransport {
    
    public func getScheme() -> McuMgrScheme {
        return .ble
    }
    
    public func send<T: McuMgrResponse>(data: Data, callback: @escaping McuMgrCallback<T>) {
        dispatchQueue.async {
            // Max concurrent opertaion count is set to 1, so operations are
            // executed one after another. A new one will be started when the
            // queue is empty, or the when the last operation finishes.
            self.operationQueue.addOperation {
                for _ in 0..<McuMgrBleTransport.MAX_RETRIES {
                    let retry = self._send(data: data, callback: callback)
                    if !retry {
                        break
                    }
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
    /// - returns: True if the send should be retried until the max retries
    ///   has been met, false if it has been handled.
    private func _send<T: McuMgrResponse>(data: Data, callback: @escaping McuMgrCallback<T>) -> Bool {
        // Is Bluetooth operational?
        if centralManager.state == .poweredOff || centralManager.state == .unsupported {
            log(msg: "Central Manager powered off", atLevel: .warning)
            fail(error: McuMgrBleTransportError.centralManagerPoweredOff, callback: callback)
            return false
        }

        // We might not have a peripheral instance yet, if the Central Manager has not
        // reported that it is powered on.
        // Wait until it is ready, and timeout if we do not get a valid peripheral instance
        let targetPeripheral: CBPeripheral

        if let existing = peripheral, centralManager.state == .poweredOn {
            targetPeripheral = existing
        } else {
            // Close the lock.
            lock.close(key: Keys.awaitingCentralManager)
            
            // Wait for the setup process to complete.
            let result = lock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransport.CONNECTION_TIMEOUT))
            
            // Check for timeout, failure, or success.
            switch result {
            case .timeout:
                log(msg: "Central Manager timed out", atLevel: .warning)
                fail(error: McuMgrTransportError.connectionTimeout, callback: callback)
                return false
            case let .error(error):
                log(msg: "Central Manager failed to start: \(error)", atLevel: .warning)
                fail(error: error, callback: callback)
                return false
            case .success:
                guard let target = self.peripheral else {
                    log(msg: "Central Manager timed out", atLevel: .warning)
                    fail(error: McuMgrTransportError.connectionTimeout, callback: callback)
                    return false
                }
                // continue
                log(msg: "Central Manager  ready", atLevel: .verbose)
                targetPeripheral = target
            }
        }
        
        // Wait until the peripheral is ready.
        if smpCharacteristic == nil {
            // Close the lock.
            lock.close(key: Keys.discoveringSmpCharacteristic)
            
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
                targetPeripheral.discoverServices([McuMgrBleTransport.SMP_SERVICE])
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
                // If the peripheral's connection state is transitioning, wait
                // and retry
                sleep(10)
                log(msg: "Retry send request...", atLevel: .verbose)
                return true
            @unknown default:
                log(msg: "Unknown state", atLevel: .warning)
            }
            
            // Wait for the setup process to complete.
            let result = lock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransport.CONNECTION_TIMEOUT))
            
            // Check for timeout, failure, or success.
            switch result {
            case .timeout:
                state = .disconnected
                log(msg: "Connection timed out", atLevel: .warning)
                fail(error: McuMgrTransportError.connectionTimeout, callback: callback)
                return false
            case let .error(error):
                state = .disconnected
                log(msg: "Connection failed: \(error)", atLevel: .warning)
                fail(error: error, callback: callback)
                return false
            case .success:
                log(msg: "Device ready", atLevel: .info)
                // Continue.
            }
        }
        
        // Make sure the SMP characteristic is not nil.
        guard let smpCharacteristic = smpCharacteristic else {
            log(msg: "Missing the SMP characteristic after connection setup.", atLevel: .error)
            fail(error: McuMgrBleTransportError.missingCharacteristic, callback: callback)
            return false
        }
        
        // Close the lock.
        lock.close(key: Keys.awaitingResponse)
        
        // Check that data length does not exceed the mtu.
        let mtu = targetPeripheral.maximumWriteValueLength(for: .withoutResponse)
        if data.count > mtu {
            log(msg: "Length of data to send exceeds MTU", atLevel: .error)
            // Fail with an insufficient MTU error.
            fail(error: McuMgrTransportError.insufficientMtu(mtu: mtu) as Error, callback: callback)
            return false
        }
        
        
        // Write the value to the characteristic.
        log(msg: "-> \(data.hexEncodedString(options: .prepend0x))", atLevel: .debug)
        targetPeripheral.writeValue(data, for: smpCharacteristic, type: .withoutResponse)

        // Wait for the response.
        let result = lock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransport.TRANSACTION_TIMEOUT))
        
        switch result {
        case .timeout:
            log(msg: "Request timed out", atLevel: .error)
            fail(error: McuMgrTransportError.sendTimeout, callback: callback)
        case .error(let error):
            log(msg: "Request failed: \(error)", atLevel: .error)
            fail(error: error, callback: callback)
        case .success:
            do {
                // Build the McuMgrResponse.
                log(msg: "<- \(responseData?.hexEncodedString(options: .prepend0x) ?? "0 bytes")",
                    atLevel: .debug)
                let response: T = try McuMgrResponse.buildResponse(scheme: getScheme(),
                                                                   data: responseData)
                success(response: response, callback: callback)
            } catch {
                fail(error: error, callback: callback)
            }
        }
        return false
    }
    
    private func success<T: McuMgrResponse>(response: T, callback: @escaping McuMgrCallback<T>) {
        responseData = nil
        responseLength = nil
        lock.close()
        DispatchQueue.main.async {
            callback(response, nil)
        }
    }
    
    private func fail<T: McuMgrResponse>(error: Error, callback: @escaping McuMgrCallback<T>) {
        responseData = nil
        responseLength = nil
        lock.close()
        DispatchQueue.main.async {
            callback(nil, error)
        }
    }
    
    private func log(msg: String, atLevel level: McuMgrLogLevel) {
        logDelegate?.log(msg, ofCategory: .transport, atLevel: level)
    }
}

//******************************************************************************
// MARK: Central Manager Delegate
//******************************************************************************

extension McuMgrBleTransport: CBCentralManagerDelegate {
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let peripheral = centralManager
                .retrievePeripherals(withIdentifiers: [identifier])
                .first {
                self.peripheral = peripheral
                lock.open(key: Keys.awaitingCentralManager)
            } else {
                lock.open(McuMgrBleTransportError.centralManagerNotReady)
            }
        default:
            lock.open(McuMgrBleTransportError.centralManagerNotReady)
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
        peripheral.discoverServices([McuMgrBleTransport.SMP_SERVICE])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.identifier == peripheral.identifier else {
            return
        }
        log(msg: "Peripheral disconnected", atLevel: .info)
        peripheral.delegate = nil
        smpCharacteristic = nil
        lock.open(McuMgrTransportError.disconnected)
        state = .disconnected
        notifyStateChanged(.disconnected)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.identifier == peripheral.identifier else {
            return
        }
        log(msg: "Peripheral failed to connect", atLevel: .warning)
        lock.open(McuMgrTransportError.connectionFailed)
    }
}

//******************************************************************************
// MARK: Peripheral Delegate
//******************************************************************************

extension McuMgrBleTransport: CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Check for error.
        guard error == nil else {
            lock.open(error)
            return
        }
        
        let s = peripheral.services?
            .map({ $0.uuid.uuidString })
            .joined(separator: ", ")
            ?? "none"
        log(msg: "Services discovered: \(s)", atLevel: .verbose)
        
        // Get peripheral's services.
        guard let services = peripheral.services else {
            lock.open(McuMgrBleTransportError.missingService)
            return
        }
        // Find the service matching the SMP service UUID.
        for service in services {
            if service.uuid == McuMgrBleTransport.SMP_SERVICE {
                log(msg: "Discovering characteristics...", atLevel: .verbose)
                peripheral.discoverCharacteristics([McuMgrBleTransport.SMP_CHARACTERISTIC],
                                                   for: service)
                return
            }
        }
        lock.open(McuMgrBleTransportError.missingService)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        // Check for error.
        guard error == nil else {
            lock.open(error)
            return
        }
        
        let c = service.characteristics?
            .map({ $0.uuid.uuidString })
            .joined(separator: ", ")
            ?? "none"
        log(msg: "Characteristics discovered: \(c)", atLevel: .verbose)
        
        // Get service's characteristics.
        guard let characteristics = service.characteristics else {
            lock.open(McuMgrBleTransportError.missingCharacteristic)
            return
        }
        // Find the characteristic matching the SMP characteristic UUID.
        for characteristic in characteristics {
            if characteristic.uuid == McuMgrBleTransport.SMP_CHARACTERISTIC {
                // Set the characteristic notification if available.
                if characteristic.properties.contains(.notify) {
                    log(msg: "Enabling notifications...", atLevel: .verbose)
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    lock.open(McuMgrBleTransportError.missingNotifyProperty)
                }
                return
            }
        }
        lock.open(McuMgrBleTransportError.missingCharacteristic)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard characteristic.uuid == McuMgrBleTransport.SMP_CHARACTERISTIC else {
            return
        }
        // Check for error.
        guard error == nil else {
            lock.open(error)
            return
        }
        
        log(msg: "Notifications enabled", atLevel: .verbose)
        
        // Set the SMP characteristic.
        smpCharacteristic = characteristic
        state = .connected
        notifyStateChanged(.connected)
        
        // The SMP Service and characateristic have now been discovered and set
        // up. Signal the dispatch semaphore to continue to send the request.
        lock.open(key: Keys.discoveringSmpCharacteristic)
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard characteristic.uuid == McuMgrBleTransport.SMP_CHARACTERISTIC else {
            return
        }
        // Check for error.
        guard error == nil else {
            lock.open(error)
            return
        }
        guard let data = characteristic.value else {
            lock.open(McuMgrTransportError.badResponse)
            return
        }
        
        // Get the expected length from the response data.
        if responseData == nil {
            // If we do not have any current response data, this is the initial
            // packet in a potentially fragmented response. Get the expected
            // length of the full response and initialize the responseData with
            // the expected capacity.
            guard let len = McuMgrResponse.getExpectedLength(scheme: getScheme(), responseData: data) else {
                lock.open(McuMgrTransportError.badResponse)
                return
            }
            responseData = Data(capacity: len)
            responseLength = len
        }
                
        // Append the response data.
        responseData!.append(data)
        
        // If we have recevied all the bytes, signal the waiting lock.
        if responseData!.count >= responseLength! {
            lock.open(key: Keys.awaitingResponse)
        }
    }
}

//******************************************************************************
// MARK: Result Lock Keys
//******************************************************************************

extension McuMgrBleTransport {
    
    /// Keys for ResultLock
    private struct Keys {
        static let awaitingCentralManager: ResultLockKey = "McuMgrBleTransport.awaitingCentralManager"
        static let discoveringSmpCharacteristic: ResultLockKey = "McuMgrBleTransport.discoveringSmpCharacteristic"
        static let awaitingResponse: ResultLockKey = "McuMgrBleTransport.awaitingResponse"
    }
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
