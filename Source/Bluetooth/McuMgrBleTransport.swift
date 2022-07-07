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
    internal var peripheral: CBPeripheral?
    /// The CBCentralManager instance from which the peripheral was obtained.
    /// This is used to connect and cancel connection.
    internal let centralManager: CBCentralManager
    /// The queue used to buffer reqeusts when another one is in progress.
    private let operationQueue: OperationQueue
    /// Lock used to wait for callbacks before continuing the request. This lock
    /// is used to wait for the device to setup (i.e. connection, descriptor)
    /// and the device to be received.
    internal let connectionLock: ResultLock
    /// Used to track multiple write requests and their responses.
    internal var writeState: McuMgrBleTransportWriteState
    /// Used to track the Sequence Number the chunked responses belong to.
    internal var previousUpdateNotificationSequenceNumber: UInt8?
    
    /// SMP Characteristic object. Used to write requests and receive
    /// notificaitons.
    internal var smpCharacteristic: CBCharacteristic?
    
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
    
    /// Set to values larger than 1 to enable Parallel Writes
    ///
    /// Features like SMP Pipelining are based on the concept of multiple packet transmissions happening
    /// at the same time and waiting for their responses as they're received. By default,`McuMgrBleTransport`
    /// only sends one Data transmission at a time. But if set to higher values, calls to
    /// ``send(data: Data, timeout: Int, callback: @escaping McuMgrCallback<T>)`` will be handled
    /// concurrently.
    public var numberOfParallelWrites: Int {
        set {
            operationQueue.maxConcurrentOperationCount = max(1, newValue)
        }
        get {
            operationQueue.maxConcurrentOperationCount
        }
    }
    
    /// Enable when calling ``send(data: Data, timeout: Int, callback: @escaping McuMgrCallback<T>)``
    /// with `Data` values larger than MTU Size, such as when SMP Reassembly feature is enabled.
    ///
    /// If the Data being sent is larger than the MTU Size, this property  should be enabled so it's cut-down
    /// to MTU Size so as to keep within each transmission packet's maximum (MTU) size limit. Otherwise, it's
    /// likely that CoreBluetooth will not send the Data.
    public var chunkSendDataToMtuSize: Bool = false
    
    public internal(set) var state: PeripheralState = .disconnected {
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
        self.centralManager = CBCentralManager(delegate: nil, queue: .global(qos: .userInitiated))
        self.identifier = targetIdentifier
        self.connectionLock = ResultLock(isOpen: false)
        self.writeState = McuMgrBleTransportWriteState()
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
    
    public func send<T: McuMgrResponse>(data: Data, timeout: Int, callback: @escaping McuMgrCallback<T>) {
        operationQueue.addOperation {
            for i in 0..<McuMgrBleTransportConstant.MAX_RETRIES {
                switch self._send(data: data, timeoutInSeconds: timeout) {
                case .failure(McuMgrTransportError.waitAndRetry):
                    sleep(UInt32(McuMgrBleTransportConstant.WAIT_AND_RETRY_INTERVAL))
                    self.log(msg: "Retry \(i + 1)", atLevel: .info)
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
    
    internal func notifyStateChanged(_ state: McuMgrTransportState) {
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
    private func _send(data: Data, timeoutInSeconds: Int) -> Result<Data, Error> {
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
            
            switch result {
            case let .failure(error):
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
            let result = connectionLock.block(timeout: DispatchTime.now() + .seconds(timeoutInSeconds))
            resetConnectionLock()
            
            switch result {
            case let .failure(error):
                state = .disconnected
                return .failure(error)
            case .success:
                log(msg: "Device ready", atLevel: .info)
            }
        }
        
        // Make sure the SMP characteristic is not nil.
        guard let smpCharacteristic = smpCharacteristic else {
            return .failure(McuMgrBleTransportError.missingCharacteristic)
        }
        
        guard let sequenceNumber = data.readMcuMgrHeaderSequenceNumber() else {
            return .failure(McuMgrTransportError.badHeader)
        }
        
        let writeLock = ResultLock(isOpen: false)
        writeLock.close()
        writeState.newWrite(sequenceNumber: sequenceNumber, lock: writeLock)
        
        let mtu = targetPeripheral.maximumWriteValueLength(for: .withoutResponse)
        if chunkSendDataToMtuSize {
            var dataChunks = [Data]()
            var dataChunksSize = 0
            while dataChunksSize < data.count {
                let i = dataChunks.count
                let chunkSize = min(data.count - dataChunksSize, mtu)
                dataChunksSize += chunkSize
                dataChunks.append(data[(i * mtu)..<(i * mtu + chunkSize)])
            }
            
            guard dataChunksSize == data.count else {
                return .failure(McuMgrTransportError.sendFailed)
            }
            
            for chunk in dataChunks {
                log(msg: "-> \(chunk.hexEncodedString(options: .prepend0x))", atLevel: .debug)
                targetPeripheral.writeValue(chunk, for: smpCharacteristic, type: .withoutResponse)
            }
        } else {
            // No SMP Reassembly Supported. So no 'chunking'.
            guard data.count <= mtu else {
                return .failure(McuMgrTransportError.insufficientMtu(mtu: mtu))
            }
            
                log(msg: "-> \(data.hexEncodedString(options: .prepend0x))", atLevel: .debug)
            targetPeripheral.writeValue(data, for: smpCharacteristic, type: .withoutResponse)
        }

        // Wait for the didUpdateValueFor(characteristic:) to open the lock.
        let result = writeLock.block(timeout: DispatchTime.now() + .seconds(timeoutInSeconds))
        
        defer {
            writeState.completedWrite(sequenceNumber: sequenceNumber)
        }
        
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success:
            guard let returnData = writeState[sequenceNumber]?.chunk else {
                return .failure(McuMgrTransportError.badHeader)
            }            
            log(msg: "<- \(returnData.hexEncodedString(options: .prepend0x))", atLevel: .debug)
            return .success(returnData)
        }
    }
    
    internal func resetConnectionLock() {
        connectionLock.close()
    }
    
    internal func log(msg: @autoclosure () -> String, atLevel level: McuMgrLogLevel) {
        logDelegate?.log(msg(), ofCategory: .transport, atLevel: level)
    }
}

// MARK: - McuMgrBleTransportConstant

public enum McuMgrBleTransportConstant {
    
    public static let SMP_SERVICE = CBUUID(string: "8D53DC1D-1DB7-4CD3-868B-8A527460AA84")
    public static let SMP_CHARACTERISTIC = CBUUID(string: "DA2E7828-FBCE-4E01-AE9E-261174997C48")
    
    /// Max number of retries until the transaction is failed.
    internal static let MAX_RETRIES = 3
    /// The interval to wait before attempting a transaction again in seconds.
    internal static let WAIT_AND_RETRY_INTERVAL = 10
    /// Connection timeout in seconds.
    internal static let CONNECTION_TIMEOUT = 20
}

// MARK: - McuMgrBleTransportKey

internal enum McuMgrBleTransportKey: ResultLockKey {
    case awaitingCentralManager = "McuMgrBleTransport.awaitingCentralManager"
    case discoveringSmpCharacteristic = "McuMgrBleTransport.discoveringSmpCharacteristic"
}

// MARK: - McuMgrBleTransportError

public enum McuMgrBleTransportError: Error, LocalizedError {
    case centralManagerPoweredOff
    case centralManagerNotReady
    case missingService
    case missingCharacteristic
    case missingNotifyProperty
    
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
