//
//  McuMgrPackage.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 18/1/22.
//  Copyright © 2022 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import ZIPFoundation

// MARK: - McuMgrPackage

public struct McuMgrPackage {
    
    public let images: [ImageManager.Image]
    public let envelope: McuMgrSuitEnvelope?
    let resources: [ImageManager.Image]?
    public let manifest: McuMgrManifest?
    
    // MARK: - Init
    
    public init(from url: URL) throws {
        switch UTI.forFile(url) {
        case .bin:
            self.images = try [ImageManager.Image(fromBinFile: url)]
            self.envelope = nil
            self.resources = nil
            self.manifest = nil
        case .zip:
            self = try Self.extractImageFromZipFile(from: url)
        case .suit:
            self = try Self.extractImageFromSuitFile(from: url)
        default:
            throw McuMgrPackage.Error.notAValidDocument
        }
    }
    
    private init(images: [ImageManager.Image], envelope: McuMgrSuitEnvelope?,
                 resources: [ImageManager.Image]?, manifest: McuMgrManifest?) {
        self.images = images
        self.envelope = envelope
        self.resources = resources
        self.manifest = manifest
    }
    
    // MARK: - API
    
    public var isForSUIT: Bool { envelope != nil }
    
    public func imageName(at index: Int) -> String {
        guard let name = images[index].name else {
            let coreName: String
            switch images[index].image {
            case 0:
                coreName = "App Core"
            case 1:
                coreName = "Net Core"
            default:
                coreName = "Image \(index)"
            }
            return "\(coreName) Slot \(images[index].slot)"
        }
        return name
    }
    
    public func image(forResource resource: FirmwareUpgradeResource) -> ImageManager.Image? {
        switch resource {
        case .file(let name):
            return resources?.first(where: {
                ($0.name?.caseInsensitiveCompare(name)) == .orderedSame
            })
        }
    }
    
    public func sizeString() -> String {
        var sizeString = ""
        for (i, image) in images.enumerated() {
            sizeString += "\(image.data.count) bytes (\(imageName(at: i)))"
            guard i != images.count - 1 else { continue }
            sizeString += "\n"
        }
        return sizeString
    }
    
    public func hashString() -> String {
        var result = ""
        for (i, image) in images.enumerated() {
            let hashString = image.hash.hexEncodedString(options: .upperCase)
            result += "0x\(hashString.prefix(6))...\(hashString.suffix(6)) (\(imageName(at: i)))"
            guard i != images.count - 1 else { continue }
            result += "\n"
        }
        return result
    }
}

// MARK: - McuMgrPackage.Error

public extension McuMgrPackage {
    
    enum Error: Swift.Error, LocalizedError {
        case deniedAccessToScopedResource, notAValidDocument, unableToAccessCacheDirectory
        case manifestFileNotFound, manifestImageNotFound
        case resourceNotFound(_ resource: FirmwareUpgradeResource)
        
        public var errorDescription: String? {
            switch self {
            case .deniedAccessToScopedResource:
                return "Access to Scoped Resource (iCloud?) Denied."
            case .notAValidDocument:
                return "This is not a valid file for DFU."
            case .unableToAccessCacheDirectory:
                return "We were unable to access the Cache Directory."
            case .manifestFileNotFound:
                return "DFU Manifest File not found."
            case .manifestImageNotFound:
                return "DFU Image specified in Manifest not found."
            case .resourceNotFound(let resource):
                return "Unable to find requested \(resource.description) resource."
            }
        }
    }
}

// MARK: - Private

fileprivate extension McuMgrPackage {
    
    static func extractImageFromSuitFile(from url: URL) throws -> Self {
        let envelope = try McuMgrSuitEnvelope(from: url)
        let algorithm = McuMgrSuitDigest.Algorithm.sha256
        guard let hash = envelope.digest.hash(for: algorithm) else {
            throw McuMgrSuitParseError.supportedAlgorithmNotFound
        }
        return McuMgrPackage(images: [ImageManager.Image(image: 0, hash: hash, data: envelope.data)], envelope: envelope, resources: nil, manifest: nil)
    }
    
    static func extractImageFromZipFile(from url: URL) throws -> Self {
        guard let cacheDirectoryPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else {
            throw McuMgrPackage.Error.unableToAccessCacheDirectory
        }
        
        let unzipLocationPath = cacheDirectoryPath + "/" + UUID().uuidString + "/"
        let unzipLocationURL = URL(fileURLWithPath: unzipLocationPath, isDirectory: true)
        
        let fileManager = FileManager()
        try fileManager.createDirectory(atPath: unzipLocationPath,
                                        withIntermediateDirectories: false)
        try fileManager.unzipItem(at: url, to: unzipLocationURL)
        let unzippedURLs = try fileManager.contentsOfDirectory(at: unzipLocationURL, includingPropertiesForKeys: nil, options: [])
        
        guard let dfuManifestURL = unzippedURLs.first(where: { $0.pathExtension == "json" }) else {
            throw McuMgrPackage.Error.manifestFileNotFound
        }
        let manifest = try McuMgrManifest(from: dfuManifestURL)
        let images: [ImageManager.Image]
        let envelope: McuMgrSuitEnvelope?
        let resources: [ImageManager.Image]?
        if let envelopeFile = manifest.envelopeFile() {
            guard let envelopeURL = unzippedURLs.first(where: { $0.absoluteString.contains(envelopeFile.file) }) else {
                throw McuMgrPackage.Error.manifestImageNotFound
            }
            envelope = try McuMgrSuitEnvelope(from: envelopeURL)
            resources = try manifest.files
                .filter({ $0.content != .suitEnvelope })
                .compactMap({ file in
                    guard let imageURL = unzippedURLs.first(where: { $0.absoluteString.contains(file.file) }) else {
                        return nil
                    }
                    let data = try Data(contentsOf: imageURL)
                    // Hash does not matter here. Wish I could get proper hash(es) for
                    // resources. But in SUIT, we can't.
                    return ImageManager.Image(file, hash: Data(), data: data)
                })
            images = [envelope?.image()].compactMap({ $0 })
        } else {
            images = try manifest.files.compactMap { manifestFile -> ImageManager.Image in
                guard let imageURL = unzippedURLs.first(where: { $0.absoluteString.contains(manifestFile.file) }) else {
                    throw McuMgrPackage.Error.manifestImageNotFound
                }
                let imageData = try Data(contentsOf: imageURL)
                let imageHash = try McuMgrImage(data: imageData).hash
                return ImageManager.Image(manifestFile, hash: imageHash, data: imageData)
            }
            envelope = nil
            resources = nil
        }
        
        try unzippedURLs.forEach { url in
            try fileManager.removeItem(at: url)
        }
        return McuMgrPackage(images: images, envelope: envelope, resources: resources, manifest: manifest)
    }
}

// MARK: - Image Extension

fileprivate extension ImageManager.Image {
    
    init(fromBinFile url: URL) throws {
        let binData = try Data(contentsOf: url)
        let binHash = try McuMgrImage(data: binData).hash
        self.init(image: 0, hash: binHash, data: binData)
    }
}
