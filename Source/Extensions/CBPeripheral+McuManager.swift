/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public extension CBPeripheral {
    public func getTransporter() -> McuMgrBleTransport {
        return McuMgrBleTransport.getInstance(self)
    }
    public func getDefaultManager() -> DefaultManager {
        return DefaultManager(transporter: getTransporter())
    }
    public func getImageManager() -> ImageManager {
        return ImageManager(transporter: getTransporter())
    }
    public func getLogManager() -> LogManager {
        return LogManager(transporter: getTransporter())
    }
    public func getConfigManager() -> ConfigManager {
        return ConfigManager(transporter: getTransporter())
    }
    public func getStatsManager() -> StatsManager {
        return StatsManager(transporter: getTransporter())
    }
}
