/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit

extension UIColor {
    
    static let accent: UIColor = #colorLiteral(red: 0, green: 0.5483048558, blue: 0.8252354264, alpha: 1)
    
    static let nordic: UIColor = #colorLiteral(red: 0, green: 0.7181802392, blue: 0.8448022008, alpha: 1)
    
    static let zephyr: UIColor = #colorLiteral(red: 0.231372549, green: 0.2431372549, blue: 0.3058823529, alpha: 1)
    
    static let nordicBlue: UIColor = #colorLiteral(red: 0, green: 0.5483048558, blue: 0.8252354264, alpha: 1)
    
    static let nordicGreen: UIColor = #colorLiteral(red: 0.298, green: 0.733, blue: 0.349, alpha: 1)
    
    static let nordicRed: UIColor = #colorLiteral(red: 0.961, green: 0.341, blue: 0.314, alpha: 1)
    
    static var primary: UIColor {
        if #available(iOS 13.0, *) {
            return .label
        } else {
            return .black
        }
    }
    
    static var secondary: UIColor {
        if #available(iOS 13.0, *) {
            return .secondaryLabel
        } else {
            return .gray
        }
    }
    
    static func dynamicColor(light: UIColor, dark: UIColor) -> UIColor {
        if #available(iOS 13.0, *) {
            return UIColor { (traitCollection) -> UIColor in
                return traitCollection.userInterfaceStyle == .light ? light : dark
            }
        } else {
            return light
        }
    }
    
}
