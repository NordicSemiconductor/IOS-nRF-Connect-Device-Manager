//
//  McuMgrManifest.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 18/1/22.
//  Copyright © 2022 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - McuMgrManifest

public struct McuMgrManifest: Codable {
    
    public let formatVersion: Int
    public let time: Int
    public let files: [File]
    
    enum CodingKeys: String, CodingKey {
        case formatVersion = "format-version"
        case time, files
    }
    
    static let LoadAddressRegEx: NSRegularExpression! =
        try? NSRegularExpression(pattern: #"\"load_address\":0x[0-9a-z]+,"#, options: [.caseInsensitive])
    
    public init(from url: URL) throws {
        guard let data = try? Data(contentsOf: url),
              let stringData = String(data: data, encoding: .utf8) else {
                  throw Error.unableToRead
        }
        
        let stringWithoutSpaces = String(stringData.filter { !" \n\t\r".contains($0) })
        let modString = Self.LoadAddressRegEx.stringByReplacingMatches(in: stringWithoutSpaces, options: [], range: NSRange(stringWithoutSpaces.startIndex..<stringWithoutSpaces.endIndex, in: stringWithoutSpaces), withTemplate: " ")
        guard let cleanData = modString.data(using: .utf8) else {
            throw Error.unableToParseJSON
        }
        do {
            self = try JSONDecoder().decode(McuMgrManifest.self, from: cleanData)
        } catch {
            throw Error.unableToDecodeJSON
        }
    }
}

// MARK: - McuMgrManifest.File

extension McuMgrManifest {
    
    public struct File: Codable {
        
        public let size: Int
        public let file: String
        public let modTime: Int
        public let mcuBootVersion: String?
        public let type: String
        public let board: String
        public let soc: String
        public let loadAddress: Int
        
        public var image: Int {
            _image ?? _imageIndex ?? 0
        }
        
        private let _image: Int?
        private let _imageIndex: Int?
        
        // swiftlint:disable nesting
        enum CodingKeys: String, CodingKey {
            case size, file
            case modTime = "modtime"
            case mcuBootVersion = "version_MCUBOOT"
            case type, board, soc
            case loadAddress = "load_address"
            case _image = "image"
            case _imageIndex = "image_index"
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            size = try values.decode(Int.self, forKey: .size)
            file = try values.decode(String.self, forKey: .file)
            modTime = try values.decode(Int.self, forKey: .modTime)
            mcuBootVersion = try? values.decode(String.self, forKey: .mcuBootVersion)
            type = try values.decode(String.self, forKey: .type)
            board = try values.decode(String.self, forKey: .board)
            soc = try values.decode(String.self, forKey: .soc)
            loadAddress = try values.decode(Int.self, forKey: .loadAddress)
            _image = try? values.decode(Int.self, forKey: ._image)
            let imageIndexString = try? values.decode(String.self, forKey: ._imageIndex)
            guard let imageIndexString = imageIndexString else {
                _imageIndex = nil
                return
            }
            
            guard let imageIndex = Int(imageIndexString) else {
                throw DecodingError.dataCorruptedError(forKey: ._imageIndex, in: values,
                                                       debugDescription: "`imageIndex` could not be parsed from String to Int.")
            }
            _imageIndex = imageIndex
        }
    }
}

// MARK: - McuMgrManifest.Error

extension McuMgrManifest {
    
    enum Error: Swift.Error, LocalizedError {
        case unableToRead, unableToParseJSON, unableToDecodeJSON
        
        var errorDescription: String? {
            switch self {
            case .unableToRead:
                return "Unable to Read Manifest JSON File."
            case .unableToParseJSON:
                return "Unable to Parse Manifest JSON File."
            case .unableToDecodeJSON:
                return "Unable to Decode Manifest JSON File."
            }
        }
    }
}
