/*
 * Copyright (c) 2025 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Errors specific to Memfault MDS operations
public enum MemfaultError: LocalizedError {
    
    case mdsServiceNotFound
    case characteristicNotFound(String)
    case deviceIdentifierReadFailed
    case dataURIReadFailed
    case authenticationDataInvalid
    case chunkDataInvalid
    case networkError(Error)
    case deviceNotConnected
    case notificationSetupFailed
    case uploadFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .mdsServiceNotFound:
            return "MDS service not found on device"
        case .characteristicNotFound(let name):
            return "MDS characteristic '\(name)' not found"
        case .deviceIdentifierReadFailed:
            return "Failed to read device identifier"
        case .dataURIReadFailed:
            return "Failed to read data URI"
        case .authenticationDataInvalid:
            return "Invalid authentication data"
        case .chunkDataInvalid:
            return "Invalid chunk data received"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .deviceNotConnected:
            return "Device is not connected"
        case .notificationSetupFailed:
            return "Failed to setup notifications"
        case .uploadFailed(let error):
            return "Upload failed: \(error.localizedDescription)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .mdsServiceNotFound:
            return "The device does not expose the Memfault Diagnostic Service"
        case .characteristicNotFound:
            return "Required MDS characteristic is missing"
        case .deviceIdentifierReadFailed, .dataURIReadFailed:
            return "Unable to read device configuration"
        case .authenticationDataInvalid:
            return "Device authentication failed"
        case .chunkDataInvalid:
            return "Corrupted diagnostic data"
        case .networkError:
            return "Unable to connect to Memfault servers"
        case .deviceNotConnected:
            return "Bluetooth connection lost"
        case .notificationSetupFailed:
            return "Unable to receive data from device"
        case .uploadFailed:
            return "Data upload to Memfault failed"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .mdsServiceNotFound:
            return "Enable the MDS service in your device firmware"
        case .characteristicNotFound:
            return "Update your device firmware to include all MDS characteristics"
        case .deviceIdentifierReadFailed, .dataURIReadFailed:
            return "Reconnect to the device and try again"
        case .authenticationDataInvalid:
            return "Check device authentication configuration"
        case .chunkDataInvalid:
            return "Reset the device and try again"
        case .networkError:
            return "Check your internet connection"
        case .deviceNotConnected:
            return "Reconnect to the device"
        case .notificationSetupFailed:
            return "Disconnect and reconnect to the device"
        case .uploadFailed:
            return "Retry the upload or check network connectivity"
        }
    }
}