//
//  ObservabilityState.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 4/11/25.
//  Copyright © 2025 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - ObservabilityState

nonisolated
struct ObservabilityState: Codable {
    
    // MARK: Properties
    
    internal var pendingUploads = [UUID: [ObservabilityChunk]]()
    
    // MARK: API
    
    mutating func add(_ chunks: [ObservabilityChunk], for identifier: UUID) {
        if pendingUploads[identifier] == nil {
            pendingUploads[identifier] = [ObservabilityChunk]()
        }
        
        pendingUploads[identifier]?.append(contentsOf: chunks)
        pendingUploads[identifier]?.sorted {
            return $0.sequenceNumber < $1.sequenceNumber && $0.timestamp < $1.timestamp
        }
        saveToDisk()
    }
    
    func nextChunk(for identifier: UUID) -> ObservabilityChunk? {
        return pendingUploads[identifier]?.first
    }
    
    mutating func finishedUploading(_ chunk: ObservabilityChunk, from identifier: UUID) {
        guard let index = pendingUploads[identifier]?.firstIndex(of: chunk) else {
            return
        }
        pendingUploads[identifier]?.remove(at: index)
        saveToDisk()
    }
}

// MARK: Save / Restore

extension ObservabilityState {
    
    mutating func restoreFromDisk() {
        guard let url = Self.stateURL(),
              let data = try? Data(contentsOf: url) else { return }
        
        if #available(iOS 14.0, *) {
            guard let restored = try? data.decompress(as: Self.self) else { return }
            self = restored
        } else {
            guard let restored = try? JSONDecoder().decode(Self.self, from: data) else { return }
            self = restored
        }
    }
    
    func saveToDisk() {
        let selfCopy = self
        guard let url = Self.stateURL() else { return }
        
        Task.detached(name: #function, priority: .utility) {
            guard let data = try? JSONEncoder().encode(self) else { return }
            do {
                let urlDirectory = url.deletingLastPathComponent()
                try Self.createDirectoryIfNecessary(at: urlDirectory)
                if #available(iOS 14.0, *) {
                    try data.compressed().write(to: url, options: [.atomic, .completeFileProtection])
                } else {
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                }
            } catch {
                print("ERROR: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: Static Helpers
    
    static func stateURL() -> URL? {
        guard let storageURL = applicationStorageDirectory() else { return nil }
        if #available(iOS 14.0, macCatalyst 14.0, macOS 11.0,  *) {
            return storageURL.appendingPathComponent("ObservabilityState.json", conformingTo: .json)
        } else {
            return storageURL.appendingPathComponent("ObservabilityState.json", isDirectory: false)
        }
    }
    
    static func createDirectoryIfNecessary(at directoryURL: URL) throws {
        var isDirectory: ObjCBool = false
        let directoryPath = directoryURL.path
        let exists = FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return
        }
        
        print("\(directoryPath) does not exist. Creating it.")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
    
    static func applicationStorageDirectory() -> URL? {
        var storageDirectory: URL?
        if #available(iOS 16.0, macCatalyst 16.0, macOS 13.0, *) {
            storageDirectory = .libraryDirectory
        } else {
            storageDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        }
        storageDirectory = storageDirectory?.appendingPathComponent("iOSOtaLibrary", isDirectory: true)
        return storageDirectory
    }
}
