//
//  HTTPRequest.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 27/04/2026.
//

import Foundation
import iOS_Common_Libraries

extension HTTPRequest {

    // MARK: otaLibraryUserAgent
    
    static func otaLibraryUserAgent() -> String {
        let bundle = Bundle(for: OTAManager.self)
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "iOSOtaLibraryClient"
        
        let appVersion = Constant.appVersion(forBundleWithClass: OTAManager.self)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let darwinVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Get CFNetwork version from the system
        let cfNetworkVersion = Bundle(identifier: "com.apple.CFNetwork")?
            .object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "Unknown"

        return "\(appName) \(appVersion)/ CFNetwork/\(cfNetworkVersion) Darwin/\(darwinVersion)"
    }
}
