//
//  AppMainSceneDelegate.swift
//  nRF Connect Device Manager
//
//  Created by Dinesh Harjani on 20/3/26.
//  Copyright © 2026 Nordic Semiconductor ASA. All rights reserved.
//

import UIKit

// MARK: - AppMainSceneDelegate

final class AppMainSceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    // MARK: Properties
    
    internal var window: UIWindow?
    
    // MARK: scene(:willConnectTo:options:)
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Confirm the scene is a window scene in iOS or iPadOS.
        guard let windowScene = scene as? UIWindowScene else { return }
        
        // Override point for customization after application launch.
        UserDefaults.standard.register(defaults: [
            "filterByUuid" : true,
            "filterByRssi" : false
        ])
        
        window = UIWindow(windowScene: windowScene)
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let controller = storyboard.instantiateViewController(identifier: "rootVC")
        window?.rootViewController = controller
        window?.tintColor = .dynamicColor(light: .accent, dark: .nordic)
        window?.makeKeyAndVisible()
    }
}

// MARK: - AppMainScene

final class AppMainScene: UIWindowScene {
    
    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: UICoordinateSpace, interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation, traitCollection previousTraitCollection: UITraitCollection) {
        print(#function)
    }
}
