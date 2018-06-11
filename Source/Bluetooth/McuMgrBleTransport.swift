/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class McuMgrBleTransport: NSObject {
    
    private let TAG: String
    
    private static let MAX_RETRIES = 3
    private static let TIMEOUT = 10
    
    public static let SMP_SERVICE = CBUUID(string: "8D53DC1D-1DB7-4CD3-868B-8A527460AA84")
    public static let SMP_CHARACTERISTIC = CBUUID(string: "DA2E7828-FBCE-4E01-AE9E-261174997C48")
    
    private var peripheral: CBPeripheral
    private var bleCentralManager: BleCentralManager
    private var dispatchQueue: DispatchQueue
    private var lock: ResultLock
    
    private var smpService: CBService?
    private var smpCharacteristic: CBCharacteristic?
    
    // Used to store fragmented response data
    private var responseData: Data?
    
    //*******************************************************************************************
    // MARK: Singleton
    //*******************************************************************************************
    
    private static var transporters = [CBPeripheral:McuMgrBleTransport]()
    private static let lock = NSObject()
    
    /// Get the shared isntance of the McuMgrBleTransporter for a given peripheral
    public static func getInstance(_ forPeripheral: CBPeripheral) -> McuMgrBleTransport {
        objc_sync_enter(McuMgrBleTransport.lock)
        var transporter = McuMgrBleTransport.transporters[forPeripheral]
        if transporter == nil {
            transporter = McuMgrBleTransport(peripheral: forPeripheral)
        }
        McuMgrBleTransport.transporters.updateValue(transporter!, forKey: forPeripheral)
        objc_sync_exit(McuMgrBleTransport.lock)
        return transporter!
    }
    
    /// Private initializer
    private init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.TAG = "SMP\(peripheral.name ?? "Unknown") (\(peripheral.identifier.uuidString.prefix(4)))"
        self.bleCentralManager = BleCentralManager.getInstance()
        self.dispatchQueue = DispatchQueue(label: "McuMgrBleTransport")
        lock = ResultLock(isOpen: false)
        super.init()
        self.bleCentralManager.addDelegate(self)
    }
}

//*******************************************************************************************
// MARK: McuMgrTransport
//*******************************************************************************************

extension McuMgrBleTransport: McuMgrTransport {
    public func getScheme() -> McuMgrScheme {
        return .ble
    }
    
    public func send<T: McuMgrResponse>(data: Data, callback: @escaping McuMgrCallback<T>) {
        dispatchQueue.async {
            var sendSuccess: Bool = false
            for retryCount in 0..<McuMgrBleTransport.MAX_RETRIES {
                let retry = self._send(data: data, retry: retryCount, callback: callback)
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
    
    /// Return true if the send should be retried until the max retries has been met
    private func _send<T: McuMgrResponse>(data: Data, retry: Int, callback: @escaping McuMgrCallback<T>) -> Bool {
        Log.v(TAG, msg: "Send McuManager request to deivce (\(peripheral.state.rawValue))")
        if peripheral.state == .connecting || peripheral.state == .disconnecting {
            Log.v(TAG, msg: "Device connection state is transitioning. Wait...")
            // If the peripheral's connection state is transitioning, wait and retry
            sleep(1)
            Log.v(TAG, msg: "Woke up! Retry send request...")
            return true
        } else if smpCharacteristic == nil {
            Log.v(TAG, msg: "Device is disconnected. Setting up connection...")
            // Close the lock
            lock.close()
            
            if self.peripheral.state == .disconnected {
                // If the peripheral is disconnected, begin the setup process by connecting to the device.
                // Once the characteristic's notification is enabled, the semaphore will be signalled
                // and the request can be sent.
                bleCentralManager.connectPeripheral(peripheral)
            }
            
            // Wait for the setup process to complete
            let result = lock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransport.TIMEOUT))
            
            // Check for timeout, failure, or success
            if case .timeout = result {
                fail(error: McuMgrError.connectionTimout, callback: callback)
                return false
            } else if case let .error(error) = result {
                fail(error: error, callback: callback)
                return false
            } else if case .success = result {
                Log.v(TAG, msg: "Connection process success")
            }
        }
        
        // Make sure the SMP characteristic is not nil
        guard let smpCharacteristic = smpCharacteristic else {
            Log.e(TAG, msg: "Missing the SMP characteristic after connection setup.")
            fail(error: McuMgrError.missingCharacteristic, callback: callback)
            return false
        }
        
        // Close the lock
        lock.close()
        
        // Fragment the packet if too large
        let mtu = bleCentralManager.getMTU(peripheral: peripheral)
        for fragment in data.fragment(size: mtu) {
            Log.v(TAG, msg: "Writing request to device...")
            peripheral.writeValue(fragment, for: smpCharacteristic, type: .withoutResponse)
        }
        
        // Wait for the response
        let result = lock.block(timeout: DispatchTime.now() + .seconds(McuMgrBleTransport.TIMEOUT))
        
        if case .timeout = result {
            fail(error: McuMgrError.writeTimeout, callback: callback)
        } else if case let .error(error) = result {
            fail(error: error, callback: callback)
        } else if case .success = result {
            Log.v(TAG, msg: "Response received! (\(responseData?.description ?? "nil"))" )
            do {
                // Build the McuMgrResponse
                let response: T = try McuMgrResponse.buildResponse(scheme: getScheme(), data: responseData)
                success(response: response, callback: callback)
            } catch {
                fail(error: error, callback: callback)
                return false
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

//*******************************************************************************************
// MARK: Central Manager Delegate
//*******************************************************************************************

extension McuMgrBleTransport: CBCentralManagerDelegate {
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if self.peripheral.identifier != peripheral.identifier {
            return
        }
        Log.v(TAG, msg: "didConnectPeripheral")
        self.peripheral = peripheral
        self.peripheral.delegate = self
        self.peripheral.discoverServices([McuMgrBleTransport.SMP_SERVICE])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if self.peripheral.identifier != peripheral.identifier {
            return
        }
        Log.v(TAG, msg: "didDisconnectPeripheral")
        objc_sync_enter(self)
        self.peripheral = peripheral
        self.smpService = nil
        self.smpCharacteristic = nil
        objc_sync_exit(self)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if self.peripheral.identifier != peripheral.identifier {
            return
        }
        Log.v(TAG, msg: "didFailToConnectPeripheral")
        self.peripheral = peripheral
    }
}

//*******************************************************************************************
// MARK: Peripheral Delegate
//*******************************************************************************************

extension McuMgrBleTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Check for error
        if let error = error {
            lock.open(error)
            return
        }
        Log.v(TAG, msg: "didDiscoverServices: \(peripheral.services ?? [])")
        self.peripheral = peripheral
        // Get peripheral's services
        guard let services = peripheral.services else {
            lock.open(McuMgrError.missingService)
            return
        }
        // Find the service matching the SMP service UUID
        for service in services {
            if service.uuid == McuMgrBleTransport.SMP_SERVICE {
                // Set the smp service
                smpService = service
                peripheral.discoverCharacteristics([McuMgrBleTransport.SMP_CHARACTERISTIC], for: service)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Check for error
        if let error = error {
            lock.open(error)
            return
        }
        Log.v(TAG, msg: "didDiscoverCharacteristics: \(service.characteristics ?? [])")
        self.peripheral = peripheral
        
        // Get service's characteristics
        guard let characteristics = service.characteristics else {
            lock.open(McuMgrError.missingCharacteristic)
            return
        }
        // Find the characteristic matching the SMP characteristic UUID
        for characteristic in characteristics {
            if characteristic.uuid == McuMgrBleTransport.SMP_CHARACTERISTIC {
                // Set the characteristic notification if available
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    return
                } else {
                    lock.open(McuMgrError.missingNotification)
                }
            }
        }
        lock.open(McuMgrError.missingCharacteristic)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            lock.open(error)
            return
        }
        Log.v(TAG, msg: "didUpdateNotificationState")
        self.peripheral = peripheral
        
        // Set the smp characteristic
        smpCharacteristic = characteristic
        
        // The SMP Service and characateristic have now been discovered and set up.
        // Signal the dispatch semaphore to continue to send the request
        lock.open()
    }
    
    
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            lock.open(error)
            return
        }
        guard let data = characteristic.value else {
            lock.open(McuMgrError.emptyResponseData)
            return
        }
        Log.v(TAG, msg: "didUpdateValue: \(data)")
        // Get the expected length from the response data.
        let expectedLength: Int
        if responseData == nil {
            // If we do not have any current response data, this is the initial packet in a
            // potentially fragmented response. Get the expected length of the full response
            // and initialize the responseData with the expected capacity.
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
        Log.v(TAG, msg: "expectedLength = \(expectedLength)")
                
        // Append the response data
        responseData!.append(data)
        
        // If we have recevied all the bytes, signal the waiting lock
        if responseData!.count >= expectedLength {
            lock.open()
        }
    }
}

// TODO: add more specific errors & error messages
public enum McuMgrError: Error {
    case connectionTimout
    case writeTimeout
    case missingService
    case missingCharacteristic
    case missingNotification
    case emptyResponseData
    case badResponse
}
