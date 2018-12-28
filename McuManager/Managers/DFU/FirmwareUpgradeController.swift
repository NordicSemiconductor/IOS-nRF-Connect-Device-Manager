//
//  FirmwareUpgradeController.swift
//  McuManager
//
//  Created by Aleksander Nowakowski on 05/07/2018.
//  Copyright © 2018 Runtime. All rights reserved.
//

import Foundation

public protocol FirmwareUpgradeController {
    
    /// Pause the firmware upgrade.
    func pause()
    
    /// Resume a paused firmware upgrade.
    func resume()
    
    /// Cancel the firmware upgrade.
    func cancel()
    
    /// Returns true if the upload has been paused.
    func isPaused() -> Bool
    
    /// Returns true if the upload is in progress.
    func isInProgress() -> Bool
}
