/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import CoreBluetooth
import iOSMcuManagerLibrary

class ConnectionStateLabel: UILabel, PeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        switch state {
        case .connected:
            self.text = "CONNECTED"
        case .connecting:
            self.text = "CONNECTING..."
        case .initializing:
            self.text = "INITIALIZING..."
        case .disconnected:
            self.text = "DISCONNECTED"
        case .disconnecting:
            self.text = "DISCONNECTING..."
        }
    }

}
