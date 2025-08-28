//
//  DeviceInfoHelper.swift
//  nRF Connect Device Manager
//
//  Helper to track device information
//

import Foundation

class DeviceInfoHelper {
    struct DeviceInfo {
        let deviceIdentifier: String?
        let hardwareVersion: String?
        let softwareType: String?
        let appVersion: String?
        let projectKey: String?
        let hasMDS: Bool
        let hasDIS: Bool
    }
    
    private var lastDeviceInfo: DeviceInfo?
    
    func updateDeviceInfo(_ info: DeviceInfo) {
        lastDeviceInfo = info
    }
    
    func getLastDeviceInfo() -> DeviceInfo? {
        return lastDeviceInfo
    }
}