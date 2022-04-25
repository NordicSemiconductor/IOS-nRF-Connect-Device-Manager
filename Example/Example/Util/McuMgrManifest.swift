//
//  McuMgrManifest.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 18/1/22.
//  Copyright © 2022 Nordic Semiconductor ASA. All rights reserved.
//

import Foundation

// MARK: - McuMgrManifest

struct McuMgrManifest: Codable {
    
    let formatVersion: Int
    let time: Int
    let files: [File]
    
    enum CodingKeys: String, CodingKey {
        case formatVersion = "format-version"
        case time, files
    }
    
    static let LoadAddressRegEx: NSRegularExpression! =
        try? NSRegularExpression(pattern: #"\"load_address\":0x[0-9a-z]+,"#, options: [.caseInsensitive])
    
    init(from url: URL) throws {
        guard let data = try? Data(contentsOf: url),
              let stringData = String(data: data, encoding: .utf8) else {
                  throw Error.unableToImport
        }
        
        let stringWithoutSpaces = String(stringData.filter { !" \n\t\r".contains($0) })
        let modString = Self.LoadAddressRegEx.stringByReplacingMatches(in: stringWithoutSpaces, options: [], range: NSRange(stringWithoutSpaces.startIndex..<stringWithoutSpaces.endIndex, in: stringWithoutSpaces), withTemplate: " ")
        guard let cleanData = modString.data(using: .utf8) else {
            throw Error.unableToParseJSON
        }
        self = try JSONDecoder().decode(McuMgrManifest.self, from: cleanData)
    }
}

// MARK: - McuMgrManifest.File

extension McuMgrManifest {
    
    struct File: Codable {
        
        let size: Int
        let file: String
        let modTime: Int
        let mcuBootVersion: String?
        let type: String
        let board: String
        let soc: String
        let imageIndex: Int
        
        // swiftlint:disable nesting
        enum CodingKeys: String, CodingKey {
            case size, file
            case modTime = "modtime"
            case mcuBootVersion = "version_MCUBOOT"
            case type, board, soc
            case imageIndex = "image_index"
        }
        
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            size = try values.decode(Int.self, forKey: .size)
            file = try values.decode(String.self, forKey: .file)
            modTime = try values.decode(Int.self, forKey: .modTime)
            mcuBootVersion = try? values.decode(String.self, forKey: .mcuBootVersion)
            type = try values.decode(String.self, forKey: .type)
            board = try values.decode(String.self, forKey: .board)
            soc = try values.decode(String.self, forKey: .soc)
            let imageIndexString = try values.decode(String.self, forKey: .imageIndex)
            guard let imageIndex = Int(imageIndexString) else {
                throw DecodingError.dataCorruptedError(forKey: .imageIndex, in: values,
                                                       debugDescription: "`imageIndex` could not be parsed from String to Int.")
            }
            self.imageIndex = imageIndex
        }
    }
}

// MARK: - McuMgrManifest.Error

extension McuMgrManifest {
    
    enum Error: Swift.Error {
        case unableToImport, unableToParseJSON
    }
}
