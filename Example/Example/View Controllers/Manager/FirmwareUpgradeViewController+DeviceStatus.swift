//
//  FirmwareUpgradeViewController+DeviceStatus.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 5/9/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import iOSMcuManagerLibrary

// MARK: - DeviceStatusDelegate

extension FirmwareUpgradeViewController: DeviceStatusDelegate {
    
    func connectionStateDidChange(_ state: iOSMcuManagerLibrary.PeripheralState) {}
    
    func bootloaderNameReceived(_ name: String) {}
    
    func bootloaderModeReceived(_ mode: iOSMcuManagerLibrary.BootloaderInfoResponse.Mode) {}
    
    func bootloaderSlotReceived(_ slot: UInt64) {}
    
    func appInfoReceived(_ output: String) {}
    
    func mcuMgrParamsReceived(buffers: Int, size: Int) {}
    
    func nRFCloudStatusChanged(_ status: nRFCloudStatus) {
        cloudStatus = status
    }
}
