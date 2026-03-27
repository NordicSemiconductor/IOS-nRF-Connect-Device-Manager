/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import os.log
import iOSMcuManagerLibrary

// MARK: - AppDelegate

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: API
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {

        let configurationName = "AppMain"
        let configuration = UISceneConfiguration(name: configurationName, sessionRole: .windowApplication)
        configuration.sceneClass = AppMainScene.self
        configuration.delegateClass = AppMainSceneDelegate.self
        return configuration
    }
}

// MARK: - McuMgrLogDelegate

extension AppDelegate: McuMgrLogDelegate {
    
    public func log(_ msg: String, ofCategory category: McuMgrLogCategory, atLevel level: McuMgrLogLevel) {
        if #available(iOS 10.0, *) {
            os_log("%{public}@", log: category.log, type: level.type, msg)
        } else {
            NSLog("%@", msg)
        }
    }
    
    func minLogLevel() -> McuMgrLogLevel {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }
    
}

// MARK: - McuMgrLogLevel

extension McuMgrLogLevel {
    
    /// Mapping from Mcu log levels to system log types.
    @available(iOS 10.0, *)
    var type: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .verbose:
            return .debug
        case .info:
            return .info
        case .application:
            return .default
        case .warning:
            return .error
        case .error:
            return .fault
        }
    }
}

// MARK: - McuMgrLogCategory

extension McuMgrLogCategory {
    
    @available(iOS 10.0, *)
    var log: OSLog {
        OSLog(subsystem: Bundle.main.bundleIdentifier!, category: rawValue)
    }
}
