/*
 * Copyright (c) 2025 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Utility to detect firmware file formats based on content
public enum FirmwareFormatDetector {
    
    public enum FirmwareFormat: String {
        case zip = "zip"
        case hex = "hex"
        case bin = "bin"
        case suit = "suit"
        
        public var displayName: String {
            switch self {
            case .zip: return "ZIP Archive"
            case .hex: return "Intel HEX"
            case .bin: return "Binary"
            case .suit: return "SUIT Envelope"
            }
        }
    }
    
    /// Detect firmware format from data
    public static func detectFormat(from data: Data) -> FirmwareFormat {
        guard !data.isEmpty else { return .bin }
        
        // Check ZIP magic number: PK\x03\x04
        if data.count >= 4 && data[0] == 0x50 && data[1] == 0x4B && data[2] == 0x03 && data[3] == 0x04 {
            return .zip
        }
        
        // Check Intel HEX format (starts with ':')
        if data.first == 0x3A {
            return .hex
        }
        
        // Check SUIT envelope (CBOR format, typically starts with specific bytes)
        // SUIT envelopes often start with 0xD8 (CBOR tag)
        if data.first == 0xD8 {
            return .suit
        }
        
        // Default to binary
        return .bin
    }
    
    /// Save firmware data to temporary file with appropriate extension
    public static func saveFirmwareToTemporaryFile(_ data: Data, format: FirmwareFormat? = nil) throws -> URL {
        let detectedFormat = format ?? detectFormat(from: data)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("firmware_\(UUID().uuidString).\(detectedFormat.rawValue)")
        try data.write(to: tempURL)
        return tempURL
    }
}