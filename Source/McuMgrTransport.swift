/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

/// McuManager transport scheme.
public enum McuMgrScheme {
    case ble, coapBle, coapUdp
    
    func isCoap() -> Bool {
        return self != .ble
    }
}

/// The connectin state observer protocol.
public protocol ConnectionStateObserver: class {
    /// Called whenever the peripheral state changes.
    ///
    /// - parameter transport: the Mcu Mgr transport object.
    /// - parameter state: The new state of the peripehral.
    func peripheral(_ transport: McuMgrTransport, didChangeStateTo state: CBPeripheralState)
}

/// Mcu Mgr transport object. The transport object
/// should automatically handle connection on first request.
public protocol McuMgrTransport: class {
    /// Returns the transport scheme.
    ///
    /// - returns: The transport scheme.
    func getScheme() -> McuMgrScheme
    
    /// Sends given data using the transport object.
    ///
    /// - parameter data: The data to be sent.
    /// - parameter callback: The request callback.
    func send<T: McuMgrResponse>(data: Data, callback: @escaping McuMgrCallback<T>)
    
    /// Releases the transport object. This should disconnect the peripheral.
    func close()
    
    /// Adds the connection state observer.
    ///
    /// - parameter observer: The observer to be added.
    func addObserver(_ observer: ConnectionStateObserver);
    
    /// Removes the connection state observer.
    ///
    /// - parameter observer: The observer to be removed.
    func removeObserver(_ observer: ConnectionStateObserver);
}
