import CoreBluetooth

/// Allows providing a custom set of UUIDs for the McuMgr BLE Transport.
protocol UuidConfig {
    
    /// The SMP service UUID.
    var serviceUuid: CBUUID { get }
    
    /// The SMP characteristic UUID.
    var characteristicUuid: CBUUID { get }
}

/// The default UUID configuration for the McuMgr.
class DefaultMcuMgrUuidConfig : UuidConfig {
    let serviceUuid: CBUUID = CBUUID(string: "8D53DC1D-1DB7-4CD3-868B-8A527460AA84")
    let characteristicUuid: CBUUID = CBUUID(string: "DA2E7828-FBCE-4E01-AE9E-261174997C48")
}
