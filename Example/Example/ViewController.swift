/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import CoreBluetooth
import McuManager

class ViewController: UIViewController {
    
    // Find Device
    @IBOutlet weak var findDeviceName: UITextField!
    @IBOutlet weak var findDeviceButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!
    
    // Device Info
    @IBOutlet weak var deviceInfoView: UIView!
    @IBOutlet weak var addressLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var connectionStateLabel: UILabel!
    
    // Image State
    @IBOutlet weak var imageStateInfoView: UIView!
    @IBOutlet weak var slotLabel0: UILabel!
    @IBOutlet weak var hashLabel0: UILabel!
    @IBOutlet weak var versionLabel0: UILabel!
    @IBOutlet weak var stateLabel0: UILabel!
    @IBOutlet weak var slotLabel1: UILabel!
    @IBOutlet weak var hashLabel1: UILabel!
    @IBOutlet weak var versionLabel1: UILabel!
    @IBOutlet weak var stateLabel1: UILabel!
    @IBOutlet weak var upgradeFirmwareButton: UIButton!
    @IBOutlet weak var eraseButton: UIButton!
    
    // Firmware Upgrade
    @IBOutlet weak var firmwareUpgradeView: UIView!
    @IBOutlet weak var fileLabel: UILabel!
    @IBOutlet weak var uploadProgressLabel: UILabel!
    @IBOutlet weak var upgradeStateLabel: UILabel!
    
    var peripheral: CBPeripheral?
    var firmwareUpgradeManager: FirmwareUpgradeManager?
    var imageData: [UInt8]?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add self as a delegate to the BleCentralManager to receive connection
        // state callbacks
        BleCentralManager.getInstance().addDelegate(self)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //**************************************************************************
    // MARK: Button Actions
    //**************************************************************************
    
    /// Looks up the device name in the Text Field from BleCentralManager's list
    /// of scanned peripherals. If found, the device is connected to and setup
    @IBAction func findDevice(_ sender: Any) {
        guard let name = findDeviceName.text else {
            return
        }
        if self.peripheral?.name == name {
            return
        }
        var peripheral: CBPeripheral?
        let scannedPeripherals = BleCentralManager.getInstance().getScannedPeripherals().values
        for scannedPeripheral in scannedPeripherals {
            guard let scannedPeripheralName = scannedPeripheral.name else {
                // Peripheral does not advertise a name
                continue
            }
            
            // Check that the name matches the Text Field input
            if scannedPeripheralName == name {
                peripheral = scannedPeripheral
                break
            }
        }
        if peripheral != nil {
            //
            setupPeripheral(peripheral)
        }
    }
    
    /// Disconnect from the current peripheral and reset the UI
    @IBAction func reset(_ sender: Any) {
        hideDeviceInfoUI()
        hideImageStateUI()
        hideFirmwareUpgradeUI()
        if let peripheral = peripheral {
            BleCentralManager.getInstance().disconnectPeripheral(peripheral)
            self.peripheral = nil
        }
    }
    
    /// Select an image from documents
    @IBAction func selectImage(_ sender: Any) {
        let importMenu = UIDocumentMenuViewController(documentTypes: ["public.data", "public.content"], in: .import)
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = upgradeFirmwareButton
        present(importMenu, animated: true, completion: nil)
    }
    
    @IBAction func eraseImage(_ sender: Any) {
        self.peripheral?.getImageManager().erase(callback:  { [unowned self] (response: McuMgrResponse?, error: Error?) in
            if let error = error {
                print(error)
                return
            }
            self.getImageState()
        })
    }
    
    //**************************************************************************
    // MARK: Peripheral Actions
    //**************************************************************************
    
    /// Setup a peripheral by connecting to it and initializing the McuManagers
    /// for the device. This function also updates the Device info UI and calls
    /// getImageState().
    ///
    /// parameter peripheral: the peripheral to setup
    func setupPeripheral(_ peripheral: CBPeripheral?) {
        guard let peripheral = peripheral else {
            return
        }
        
        // Disconnect from the current peripheral
        if self.peripheral != nil {
            BleCentralManager.getInstance().disconnectPeripheral(self.peripheral!)
        }
        
        // Set the periphearl
        self.peripheral = peripheral
        
        // Connect to the peripheral
        BleCentralManager.getInstance().connectPeripheral(peripheral)
        
        // Update the UI
        updateDeviceInfoUI()
        showDeviceInfoUI()
        
        // Get the device's image state
        getImageState()
    }
    
    /// Get the connected peripheral's image state.
    func getImageState() {
        // Call the list command from the Image command group with an inline
        // callback
        peripheral?.getImageManager().list(callback: { [unowned self] (response: McuMgrImageStateResponse?, error: Error?) in
            if let error = error {
                print(error)
                return
            }
            print(response!)
            DispatchQueue.main.async {
                // Update the UI
                self.resetImageStateValues()
                self.updateImageStateUI(response: response!)
                self.showImageStateUI()
            }
        })
    }
}


//******************************************************************************
// MARK: Document Picker Delegates
//******************************************************************************

/// Presents the document picker menu
extension ViewController: UIDocumentMenuDelegate {
    func documentMenu(_ documentMenu: UIDocumentMenuViewController, didPickDocumentPicker documentPicker: UIDocumentPickerViewController) {
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
}

extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        guard let peripheral = self.peripheral else {
            return
        }
        if let imageData = dataFrom(url: url) {
            // Update Firmware upgrade UI
            fileLabel.text = url.lastPathComponent
            showFirmwareUpgradeUI()
            do {
                // Initialize the firmware upgrade manager and start the upgrade
                firmwareUpgradeManager = try FirmwareUpgradeManager(transporter: peripheral.getTransporter(), imageData: imageData, delegate: self)
                firmwareUpgradeManager?.start()
            } catch {
                showErrorDialog(error: error)
            }
        }
    }
    
    /// Get the image data from the document URL
    private func dataFrom(url: URL) -> Data? {
        var data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch {
            print("Error reading file: \(error)")
        }
        return data
    }
}

//******************************************************************************
// MARK: FimrwareUpgradeDelegate
//******************************************************************************

extension ViewController: FirmwareUpgradeDelegate {
    func didStart(manager: FirmwareUpgradeManager) {
        // Do nothing...
    }
    
    func didStateChange(previousState: FirmwareUpgradeState, newState: FirmwareUpgradeState) {
        DispatchQueue.main.async {
            self.upgradeStateLabel.text = String(describing: newState)
        }
    }
    
    func didComplete() {
        DispatchQueue.main.async {
            self.getImageState()
            let alertController = UIAlertController(title: "Firmware Upgrade Success!", message:
                "The device's firmware has been upgraded succesfully.", preferredStyle: UIAlertControllerStyle.alert)
            alertController.addAction(UIAlertAction(title: "Dismiss", style: UIAlertActionStyle.default,handler: nil))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func didFail(failedState: FirmwareUpgradeState, error: Error) {
        DispatchQueue.main.async {
            self.getImageState()
            self.showErrorDialog(error: error)
        }
    }
    
    func didCancel(state: FirmwareUpgradeState) {
        // Do nothing...
    }
    
    func didUploadProgressChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        DispatchQueue.main.async {
            let progress: Int = Int((Float(bytesSent) / Float(imageSize)) * 100.0)
            self.uploadProgressLabel.text = "\(progress)%"
        }
    }
}

//******************************************************************************
// MARK: CBCentralManagerDelegate
//******************************************************************************

extension ViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Starting Scan...")
            // Begin scanning
            BleCentralManager.getInstance().startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Update the UI on connection state changes
        updateDeviceInfoUI()
    }
}

//******************************************************************************
// MARK: UI Update Functions
//******************************************************************************

extension ViewController {

    /// Show device info UI
    func showDeviceInfoUI() {
        deviceInfoView.isHidden = false
    }
    
    /// Hide device info UI
    func hideDeviceInfoUI() {
        deviceInfoView.isHidden = true
    }
    
    /// Update device info UI
    func updateDeviceInfoUI() {
        guard let peripheral = peripheral else {
            return
        }
        addressLabel.text = peripheral.identifier.uuidString
        nameLabel.text = peripheral.name ?? "Unknown"
        switch(peripheral.state) {
        case .connected:
            connectionStateLabel.text = "Connected"
            break
        case .connecting:
            connectionStateLabel.text = "Connecting"
            break
        case .disconnecting:
            connectionStateLabel.text = "Disconnecting"
            break
        case .disconnected:
            connectionStateLabel.text = "Disconnected"
            break
        }
    }
    
    /// Show image state UI
    func showImageStateUI() {
        imageStateInfoView.isHidden = false
        upgradeFirmwareButton.isHidden = false
    }
    
    /// Hide image state UI
    func hideImageStateUI() {
        imageStateInfoView.isHidden = true
        upgradeFirmwareButton.isHidden = true
    }
    
    /// Update image state UI
    func updateImageStateUI(response: McuMgrImageStateResponse) {
        guard let images = response.images else {
            return
        }
        if images.count > 0 {
            let imageSlot0 = images[0]
            slotLabel0.text = imageSlot0.slot.description
            hashLabel0.text = Data(imageSlot0.hash).base64EncodedString()
            versionLabel0.text = imageSlot0.version
            var stateStr = ""
            if imageSlot0.active {
                stateStr.append("Active ")
            }
            if imageSlot0.pending {
                stateStr.append("Pending ")
            }
            if imageSlot0.confirmed {
                stateStr.append("Confirmed ")
            }
            if imageSlot0.bootable {
                stateStr.append("Bootable ")
            }
            if imageSlot0.permanent {
                stateStr.append("Permanent ")
            }
            stateLabel0.text = stateStr
        }
        if images.count > 1 {
            let imageSlot1 = images[1]
            slotLabel1.text = imageSlot1.slot.description
            hashLabel1.text = Data(imageSlot1.hash).base64EncodedString()
            versionLabel1.text = imageSlot1.version
            var stateStr = ""
            if imageSlot1.active {
                stateStr.append("Active ")
            }
            if imageSlot1.pending {
                stateStr.append("Pending ")
            }
            if imageSlot1.confirmed {
                stateStr.append("Confirmed ")
            }
            if imageSlot1.bootable {
                stateStr.append("Bootable ")
            }
            if imageSlot1.permanent {
                stateStr.append("Permanent ")
            }
            stateLabel1.text = stateStr
        }
    }
    
    /// Reset the image state values to "n/a"
    func resetImageStateValues() {
        slotLabel0.text = "n/a"
        versionLabel0.text = "n/a"
        hashLabel0.text = "n/a"
        stateLabel0.text = "n/a"
        slotLabel1.text = "n/a"
        versionLabel1.text = "n/a"
        hashLabel1.text = "n/a"
        stateLabel1.text = "n/a"
    }
    
    /// Shoe firmware upgrade UI
    func showFirmwareUpgradeUI() {
        firmwareUpgradeView.isHidden = false
    }
    
    /// Hide firmware upgrade UI
    func hideFirmwareUpgradeUI() {
        firmwareUpgradeView.isHidden = true
    }
    
    /// Show error dialog
    func showErrorDialog(error: Error) {
        let alertController = UIAlertController(title: "Firmware Upgrade Failed!", message:
            "\(error)", preferredStyle: UIAlertControllerStyle.alert)
        alertController.addAction(UIAlertAction(title: "Dismiss", style: UIAlertActionStyle.default,handler: nil))
        self.present(alertController, animated: true, completion: nil)
    }
}
