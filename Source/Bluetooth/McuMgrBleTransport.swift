/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class McuMgrBleTransport: NSObject {
    
    public static let SMP_SERVICE = CBUUID(string: "8D53DC1D-1DB7-4CD3-868B-8A527460AA84")
    public static let SMP_CHARACTERISTIC = CBUUID(string: "DA2E7828-FBCE-4E01-AE9E-261174997C48")
    
    /// Logging TAG.
    private let TAG: String
    
    /// Max number of retries until the transaction is failed.
    private static let MAX_RETRIES = 3
    /// Transaction timout in seconds.
    private static let TIMEOUT = 10
    
    /// The CBPeripheral for this transport to communicate with.
    private let peripheral: CBPeripheral
    /// The CBCentralManager instance from which the peripheral was obtained.
    /// This is used to connect and cancel connection.
    private let centralManager: CBCentralManager
    /// Dispatch queue for queuing requests.
    private var dispatchQueue: DispatchQueue
    /// Lock used to wait for callbacks before continuing the request. This lock
    /// is used to wait for the device to setup (i.e. connection, descriptor
    /// writes) and the device to be received.
    private var lock: ResultLock
    
    /// SMP Characteristic object. Used to write requests adn receive notificaitons.
    private var smpCharacteristic: CBCharacteristic?
    
    /// Used to store fragmented response data.
    private var responseData: Data?
    /// An array of observers.
    private var observers: [ConnectionStateObserver]
    
    /// Creates a BLE transport object for the peripheral matching given
    /// identifier. The implementation will create internal instance of
    /// CBCentralManager, and will retrieve the CBPeripheral from it.
    /// The target given as a parameter will not be used.
    /// The CBCentralManager from which the target was obtaied will not
    /// be notified about connection states.
    ///
    /// The peripheral will connect automatically if a request to it is
    /// made. To disconnect the periphera, call close().
    ///
    /// - parameter target: The BLE peripheral with Simple Managerment
    ///   Protocol (SMP) service.
    public init?(_ target: CBPeripheral) {
        self.centralManager = CBCentralManager(delegate: nil, queue: nil)
        guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [target.identifier]).first else {
            return nil
        }
        self.TAG = "SMP \(peripheral.name ?? "Unknown") (\(peripheral.identifier.uuidString.prefix(4)))"
        self.peripheral = peripheral
        self.dispatchQueue = DispatchQueue(label: "McuMgrBleTransport")
        self.lock = ResultLock(isOpen: false)
        self.observers = []
        super.init()
    }
    
    public var state: CBPeripheralState {
        return peripheral.state
    }
    
    public var name: String? {
        return peripheral.name
    }
    
    public var identifier: UUID {
        return peripheral.identifier
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
            var sendSuccess: Bool = false
            for _ in 0..<McuMgrBleTransport.MAX_RETRIES {
                let retry = self._send(data: data, callback: callback)
                if !retry {
                    sendSuccess = true
                    break
                }
            }
            if !sendSuccess {
                self.fail(error: McuMgrError.connectionTimout, callback: callback)
            }
        }
    }
    
    public func close() {
        if peripheral.state == .connected || peripheral.state == .connecting {
            Log.v(TAG, msg: "Cancelling connection...")
            notifyStateChanged(CBPeripheralState.disconnecting)
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    public func addObserver(_ observer: ConnectionStateObserver) {
        observers.append(observer)
    }
    
    public func removeObserver(_ observer: ConnectionStateObserver) {
        if let index = observers.index(where: {$0 === observer}) {
            observers.remove(at: index)
        }
    }
    
    private func notifyStateChanged(_ state: CBPeripheralState) {
        // The list of observers may be modified by each observer.
        // Better iterate a copy of it.
        let array = [ConnectionStateObserver](observers)
        for observer in array {
            observer.peripheral(self, didChangeStateTo: state)
        }
    }
    
    /// This method sends the data to the target. Before, it ensures that
    /// CBCentralManager is ready and the peripheral is connected.
    /// The peripheral will automatically be connected when it's not.
    ///
    /// - returns: True if the send should be retried until the max retries
    ///   has been met, false if it has been handled.
    private func _send<T: McuMgrResponse>(data: Data, callback: @escaping McuMgrCallback<T>) -> Bool {
        centralManager.delegate = self
        
        // Is Bluetooth operational?
        if centralManager.state == .poweredOff || centralManager.state == .unsupported {
            Log.w(TAG, msg: "Central Manager powered off")
            fail(error: McuMgrError.centralManagerPoweredOff, callback: callback)
            return false
        }
        
        // Wait until the Central Manager is ready.
        // This is required when the manager has just been created.
        if centralManager.state == .unknown {
            // Close the lock
            lock.close()
            
            // Wait for the setup process to complete.
            let result = lock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransport.TIMEOUT))
            
            // Check for timeout, failure, or success.
            switch result {
            case .timeout:
                Log.w(TAG, msg: "Central Manager timed out")
                fail(error: McuMgrError.connectionTimout, callback: callback)
                return false
            case let .error(error):
                Log.w(TAG, msg: "Central Manager failed to start: \(error)")
                fail(error: error, callback: callback)
                return false
            case .success:
                Log.v(TAG, msg: "Central Manager  ready")
                // continue
            }
        }
        
        // Wait until the peripheral is ready.
        if smpCharacteristic == nil {
            // Close the lock
            lock.close()
            
            switch peripheral.state {
            case .connected:
                // If the peripheral was already connected, but the SMP
                // characteristic has not been set, start by performing service
                // discovery. Once the characteristic's notification is enabled,
                // the semaphore will be signalled and the request can be sent.
                Log.i(TAG, msg: "Peripheral already connected")
                Log.v(TAG, msg: "Discovering services...")
                notifyStateChanged(CBPeripheralState.connecting)
                peripheral.delegate = self
                peripheral.discoverServices([McuMgrBleTransport.SMP_SERVICE])
            case .disconnected:
                // If the peripheral is disconnected, begin the setup process by
                // connecting to the device. Once the characteristic's
                // notification is enabled, the semaphore will be signalled and
                // the request can be sent.
                Log.v(TAG, msg: "Connecting...")
                notifyStateChanged(CBPeripheralState.connecting)
                centralManager.connect(peripheral)
            case .connecting:
                Log.i(TAG, msg: "Device is connecting. Wait...")
                // Do nothing. It will switch to .connected or .disconnected.
            case .disconnecting:
                Log.i(TAG, msg: "Device is disconnecting. Wait...")
                // If the peripheral's connection state is transitioning, wait and retry
                sleep(10)
                Log.v(TAG, msg: "Retry send request...")
                return true
            }
            
            // Wait for the setup process to complete.
            let result = lock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransport.TIMEOUT))
            
            // Check for timeout, failure, or success.
            switch result {
            case .timeout:
                Log.w(TAG, msg: "Connection timed out")
                fail(error: McuMgrError.connectionTimout, callback: callback)
                return false
            case let .error(error):
                Log.w(TAG, msg: "Connection failed: \(error)")
                fail(error: error, callback: callback)
                return false
            case .success:
                Log.v(TAG, msg: "Device ready")
                // continue
            }
        }
        
        // Make sure the SMP characteristic is not nil.
        guard let smpCharacteristic = smpCharacteristic else {
            Log.e(TAG, msg: "Missing the SMP characteristic after connection setup.")
            fail(error: McuMgrError.missingCharacteristic, callback: callback)
            return false
        }
        
        // Close the lock.
        lock.close()
        
        // Fragment the packet if too large.
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        for fragment in data.fragment(size: mtu) {
            Log.v(TAG, msg: "Writing request to device...")
            peripheral.writeValue(fragment, for: smpCharacteristic, type: .withoutResponse)
        }
        
        // Wait for the response.
        let result = lock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransport.TIMEOUT))
        
        switch result {
        case .timeout:
            Log.w(TAG, msg: "Request timed out")
            fail(error: McuMgrError.writeTimeout, callback: callback)
        case let .error(error):
            Log.w(TAG, msg: "Request failed: \(error)")
            fail(error: error, callback: callback)
        case .success:
            Log.i(TAG, msg: "Response received")
            do {
                // Build the McuMgrResponse.
                let response: T = try McuMgrResponse.buildResponse(scheme: getScheme(), data: responseData)
                success(response: response, callback: callback)
            } catch {
                fail(error: error, callback: callback)
            }
        }
        return false
    }
    
    private func success<T: McuMgrResponse>(response: T, callback: @escaping McuMgrCallback<T>) {
        responseData = nil
        lock.close()
        callback(response, nil)
    }
    
    private func fail<T: McuMgrResponse>(error: Error, callback: @escaping McuMgrCallback<T>) {
        responseData = nil
        lock.close()
        callback(nil, error)
    }
}

//******************************************************************************
// MARK: Central Manager Delegate
//******************************************************************************

extension McuMgrBleTransport: CBCentralManagerDelegate {
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            lock.open()
        default:
            lock.open(McuMgrError.centralManagerNotReady)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral.identifier == peripheral.identifier else {
            return
        }
        Log.i(TAG, msg: "Peripheral connected")
        Log.v(TAG, msg: "Discovering services...")
        self.peripheral.delegate = self
        self.peripheral.discoverServices([McuMgrBleTransport.SMP_SERVICE])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral.identifier == peripheral.identifier else {
            return
        }
        Log.i(TAG, msg: "Peripheral disconnected")
        self.centralManager.delegate = nil
        self.peripheral.delegate = nil
        self.smpCharacteristic = nil
        notifyStateChanged(CBPeripheralState.disconnected)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral.identifier == peripheral.identifier else {
            return
        }
        Log.i(TAG, msg: "Peripheral failed to connect")
        lock.open(McuMgrError.connectionFailed)
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
        
        Log.i(TAG, msg: "Services discovered: \(peripheral.services ?? [])")
        
        // Get peripheral's services.
        guard let services = peripheral.services else {
            lock.open(McuMgrError.missingService)
            return
        }
        // Find the service matching the SMP service UUID.
        for service in services {
            if service.uuid == McuMgrBleTransport.SMP_SERVICE {
                Log.v(TAG, msg: "Discovering characteristics...")
                peripheral.discoverCharacteristics([McuMgrBleTransport.SMP_CHARACTERISTIC], for: service)
                return
            }
        }
        lock.open(McuMgrError.missingService)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Check for error.
        guard error == nil else {
            lock.open(error)
            return
        }
        
        Log.i(TAG, msg: "Characteristics discovered: \(service.characteristics ?? [])")
        
        // Get service's characteristics.
        guard let characteristics = service.characteristics else {
            lock.open(McuMgrError.missingCharacteristic)
            return
        }
        // Find the characteristic matching the SMP characteristic UUID.
        for characteristic in characteristics {
            if characteristic.uuid == McuMgrBleTransport.SMP_CHARACTERISTIC {
                // Set the characteristic notification if available.
                if characteristic.properties.contains(.notify) {
                    Log.v(TAG, msg: "Enabling notifications...")
                    peripheral.setNotifyValue(true, for: characteristic)
                    return
                } else {
                    lock.open(McuMgrError.missingNotifyProperty)
                }
            }
        }
        lock.open(McuMgrError.missingCharacteristic)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == McuMgrBleTransport.SMP_CHARACTERISTIC else {
            return
        }
        // Check for error.
        guard error == nil else {
            lock.open(error)
            return
        }
        
        Log.i(TAG, msg: "Notifications enabled")
        
        // Set the SMP characteristic.
        smpCharacteristic = characteristic
        notifyStateChanged(CBPeripheralState.connected)
        
        // The SMP Service and characateristic have now been discovered and set
        // up. Signal the dispatch semaphore to continue to send the request.
        lock.open()
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == McuMgrBleTransport.SMP_CHARACTERISTIC else {
            return
        }
        // Check for error.
        guard error == nil else {
            lock.open(error)
            return
        }
        guard let data = characteristic.value else {
            lock.open(McuMgrError.emptyResponseData)
            return
        }
        
        Log.i(TAG, msg: "Notification received")
        
        // Get the expected length from the response data.
        let expectedLength: Int
        if responseData == nil {
            // If we do not have any current response data, this is the initial
            // packet in a potentially fragmented response. Get the expected
            // length of the full response and initialize the responseData with
            // the expected capacity.
            guard let len = McuMgrResponse.getExpectedLength(scheme: getScheme(), responseData: data) else {
                lock.open(McuMgrError.badResponse)
                return
            }
            responseData = Data(capacity: len)
            expectedLength = len
        } else {
            if let len = McuMgrResponse.getExpectedLength(scheme: getScheme(), responseData: responseData!) {
                expectedLength = len
            } else {
                lock.open(McuMgrError.badResponse)
                return
            }
        }
                
        // Append the response data.
        responseData!.append(data)
        
        // If we have recevied all the bytes, signal the waiting lock.
        if responseData!.count >= expectedLength {
            lock.open()
        }
    }
}

// TODO: Add more specific errors & error messages.
public enum McuMgrError: Error {
    case centralManagerPoweredOff
    case centralManagerNotReady
    case connectionTimout
    case connectionFailed
    case writeTimeout
    case missingService
    case missingCharacteristic
    case missingNotifyProperty
    case emptyResponseData
    case badResponse
}
