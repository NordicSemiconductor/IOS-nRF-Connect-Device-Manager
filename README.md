# McuManager iOS

A transport agnostic implementation of the McuManager protocol (aka Newt Manager (NMP), Simple Management Protocol (SMP)) for iOS. 

## Install

TODO Create Cocoa Pod and Carthage

# Introduction

McuManager is an application layer protocol used to manage and monitor microcontrollers running Apache Mynewt and Zephyr. More specifically, McuManagr implements over-the-air (OTA) firmware upgrades, log and stat collection, and file-system and configuration management.

## Command Groups

McuManager are organized by functionality into command groups. In _mcumgr-ios_, command groups are called managers and extend the `McuManager` class. The managers (groups) implemented in _mcumgr-ios_ are:

* **`DefaultManager`**: Contains commands relevant to the OS. This includes task and memory pool statistics, device time read & write, and device reset.
* **`ImageManager`**: Manage image state on the device and perform image uploads.
* **`StatsManager`**: Read stats from the device.
* **`ConfigManager`**: Read/Write config values on the device.
* **`LogManager`**: Collect logs from the device.
* **`CrashManager`**: Run crash tests on the device.
* **`RunTestManager`**: Runs tests on the device.
* **`FileSystemManager`**: Download/upload files from the device file system.

# Firmware Upgrade

Firmware upgrade is generally a four step process performed using commands from the `image` and `default` commands groups: `upload`, `test`, `reset`, and `confirm`.

This library provides a `FirmwareUpgradeManager` as a convinience for upgrading the image running on a device. 

## FirmwareUpgradeManager

A `FirmwareUpgradeManager` provides an easy way to perform firmware upgrades on a device. A `FirmwareUpgradeManager` must be initialized with an `McuMgrTransport` which defines the transport scheme and device. Once initialized, a `FirmwareUpgradeManager` can perform one firmware upgrade at a time. Firmware upgrades are started using the `start(data: Data)` method and can be paused, resumed, and canceled using `pause()`, `resume()`, and `cancel()` respectively.

#### Firmware Upgrade Mode

McuManager firmware upgrades can actually be performed in few different ways. These different upgrade modes determine the commands sent after the `upload` step. The `FirmwareUpgradeManager` can be configured to perform these upgrade variations by setting the `mode` property. The different firmware upgrade modes are as follows:

* **`.testAndConfirm`**: This mode is the **default and recommended mode** for performing upgrades due to it's ability to recover from a bad firmware upgrade. The process for this mode is `upload`, `test`, `reset`, `confirm`. 
* **`.confirmOnly`**: This mode is **not recommended**. If the device fails to boot into the new image, it will not be able to recover and will need to be re-flashed. The process for this mode is `upload`, `confirm`, `reset`.
* **`.testOnly`**: This mode is useful if you want to run tests on the new image running before confirming it manually as the primary boot image. The process for this mode is `upload`, `test`, `reset`.

### Firmware Upgrade State

`FirmwareUpgradeManager` acts as a simple, mostly linear state machine which is determined by the `Mode`. As the manager moves through the firmware upgrade process, state changes are provided through the `FirmwareUpgradeDelegate`'s `upgradeStateDidChange` method.

The `FirmwareUpgradeManager` contains an additional state, `validate`, which precedes the upload. The `validate` state checks the current image state of the device in an attempt to bypass certain states of the firmware upgrade. For example, if the image to upgrade to already exists in slot 1 on the device, the `FirmwareUpgradeManager` will skip `upload` and move directly to `test` (or `confirm` if `.confirmOnly` mode has been set) from `validate`. If the uploaded image is already active, and confirmed in slot 0, the upgrade will succeed immediately. In short, the `validate` state makes it easy to reattempt an upgrade without needing to re-upload the image or manually determine where to start.

### Example
```swift
// Initialize the BLE transporter using a scanned peripheral
let bleTransport = McuMgrBleTransport(cbPeripheral)

// Initialize the FirmwareUpgradeManager using the transport and a delegate
let dfuManager = FirmwareUpgradeManager(bleTransport, delegate)

// Start the firmware upgrade with the image data
dfuManager.start(data: imageData)
```