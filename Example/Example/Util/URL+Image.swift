//
//  URL+Image.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 18/1/22.
//  Copyright © 2022 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation
import McuManager
import ZIPFoundation

extension URL {
    
    func extractImages() throws -> [ImageManager.Image] {
        let document = UIDocument(fileURL: self)
        guard let fileType = document.fileType else {
            throw ImageExtractionError.notAValidDocument
        }
        
        if UTI.bin.typeIdentifiers.contains(fileType) {
            return try extractImageFromBinFile()
        } else if UTI.zip.typeIdentifiers.contains(fileType) {
            return try extractImageFromZipFile()
        }
        throw ImageExtractionError.notAValidDocument
    }
    
    private func extractImageFromBinFile() throws -> [ImageManager.Image] {
        let binData = try Data(contentsOf: self)
        return [ImageManager.Image(image: 0, data: binData)]
    }
    
    private func extractImageFromZipFile() throws -> [ImageManager.Image] {
        guard let cacheDirectoryPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else {
            throw ImageExtractionError.unableToAccessCacheDirectory
        }
        let cacheDirectoryURL = URL(fileURLWithPath: cacheDirectoryPath, isDirectory: true)
        
        let fileManager = FileManager()
        let contentURLs = try fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        contentURLs.forEach { url in
            _ = try? fileManager.removeItem(at: url)
        }
        
        try fileManager.unzipItem(at: self, to: cacheDirectoryURL)
        let unzippedURLs = try fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil, options: [])
        
        guard let dfuManifestURL = unzippedURLs.first(where: { $0.pathExtension == "json" }) else {
            throw ImageExtractionError.manifestFileNotFound
        }
        let manifest = try McuMgrManifest(from: dfuManifestURL)
        let images = try manifest.files.compactMap { manifestFile -> ImageManager.Image in
            guard let imageURL = unzippedURLs.first(where: { $0.absoluteString.contains(manifestFile.file) }) else {
                throw ImageExtractionError.manifestImageNotFound
            }
            let imageData = try Data(contentsOf: imageURL)
            return (manifestFile.imageIndex, imageData)
        }
        try unzippedURLs.forEach { url in
            try fileManager.removeItem(at: url)
        }
        
        return images
    }
}

// MARK: - URL.ImageExtractionError

extension URL {
    
    enum ImageExtractionError: Error {
        case deniedAccessToScopedResource, notAValidDocument, unableToAccessCacheDirectory, manifestFileNotFound, manifestImageNotFound
    }
}
