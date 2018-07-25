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
    
    // Firmware Upgrade start timestamp. Used to track the speed of the upload.
    var startTime: Date!
    
    var transport: McuMgrBleTransport?
    var centralManager: CBCentralManager!
    var firmwareUpgradeManager: FirmwareUpgradeManager?
    var imageData: [UInt8]?
    var name: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.centralManager = CBCentralManager(delegate: nil, queue: nil)
        self.centralManager.delegate = self
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
        findDeviceName.resignFirstResponder()
        self.name = name
        print("Starting Scan...")
        centralManager.scanForPeripherals(withServices: [])
    }
    
    /// Disconnect from the current peripheral and reset the UI
    @IBAction func reset(_ sender: Any) {
        print("Stopping scan...")
        centralManager.stopScan()
        hideDeviceInfoUI()
        hideImageStateUI()
        hideFirmwareUpgradeUI()
        if let transport = transport {
            transport.close()
        }
        transport = nil
    }
    
    /// Select an image from documents
    @IBAction func selectImage(_ sender: Any) {
        let importMenu = UIDocumentMenuViewController(documentTypes: ["public.data", "public.content"], in: .import)
        importMenu.delegate = self
        importMenu.popoverPresentationController?.sourceView = upgradeFirmwareButton
        present(importMenu, animated: true, completion: nil)
    }
    
    @IBAction func eraseImage(_ sender: Any) {
        guard let transport = transport else {
            return
        }
        ImageManager(transporter: transport).erase(callback:  { [unowned self] (response: McuMgrResponse?, error: Error?) in
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
    /// - parameter peripheral: The peripheral to setup.
    func setupPeripheral(_ peripheral: CBPeripheral?) {
        guard let peripheral = peripheral else {
            return
        }
        
        // Set the peripheral
        transport = McuMgrBleTransport(peripheral)
        transport!.addObserver(self)
        
        // Update the UI
        updateDeviceInfoUI()
        showDeviceInfoUI()
        
        // Get the device's image state
        getImageState()
    }
    
    /// Get the connected peripheral's image state.
    func getImageState() {
        guard let transport = transport else {
            return
        }
        // Call the list command from the Image command group with an inline
        // callback
        ImageManager(transporter: transport).list(callback: { [unowned self] (response: McuMgrImageStateResponse?, error: Error?) in
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
        guard let transport = transport else {
            return
        }
        if let imageData = dataFrom(url: url) {
            // Update Firmware upgrade UI
            fileLabel.text = url.lastPathComponent
            showFirmwareUpgradeUI()
            firmwareUpgradeManager = FirmwareUpgradeManager(transporter: transport, delegate: self)
            
            let alertController = UIAlertController(title: "Select mode", message: nil, preferredStyle: .actionSheet)
            alertController.addAction(UIAlertAction(title: "Test and confirm", style: .default) {
                action in
                self.firmwareUpgradeManager!.mode = .testAndConfirm
                self.start(imageData)
            })
            alertController.addAction(UIAlertAction(title: "Test only", style: .default) {
                action in
                self.firmwareUpgradeManager!.mode = .testOnly
                self.start(imageData)
            })
            alertController.addAction(UIAlertAction(title: "Confirm only", style: .default) {
                action in
                self.firmwareUpgradeManager!.mode = .confirmOnly
                self.start(imageData)
            })
            
            // If the device is an ipad set the popover presentation controller
            if let presenter = alertController.popoverPresentationController {
                presenter.sourceView = self.view
                presenter.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                presenter.permittedArrowDirections = []
            }
            present(alertController, animated: true)
        }
    }
    
    private func start(_ imageData: Data) {
        do {
            // Initialize the firmware upgrade manager and start the upgrade
            try self.firmwareUpgradeManager!.start(data: imageData)
        } catch {
            self.showErrorDialog(error: error)
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
    
    func upgradeDidStart(controller: FirmwareUpgradeController) {
        // Do nothing...
        startTime = Date()
    }

    func upgradeStateDidChange(from previousState: FirmwareUpgradeState, to newState: FirmwareUpgradeState) {
        DispatchQueue.main.async {
            self.upgradeStateLabel.text = String(describing: newState)
        }
    }

    func upgradeDidComplete() {
        DispatchQueue.main.async {
            self.upgradeStateLabel.text = String(describing: "complete")
            self.getImageState()
            
            let alertController = UIAlertController(title: "Firmware Upgrade Success!", message:
                "The device's firmware has been upgraded succesfully.", preferredStyle: UIAlertControllerStyle.alert)
            alertController.addAction(UIAlertAction(title: "Dismiss", style: UIAlertActionStyle.default))
            self.present(alertController, animated: true)
        }
    }
    
    func upgradeDidFail(inState state: FirmwareUpgradeState, with error: Error) {
        DispatchQueue.main.async {
            self.getImageState()
            self.showErrorDialog(error: error)
        }
    }
    
    func upgradeDidCancel(state: FirmwareUpgradeState) {
        // Do nothing...
    }
    
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        DispatchQueue.main.async {
            let progress: Int = Int((Float(bytesSent) / Float(imageSize)) * 100.0)
            let elapsed = timestamp.timeIntervalSince(self.startTime)
            let bytesPerSecond = Double(bytesSent) / elapsed
            let estimatedTime = (imageSize - bytesSent) / Int(bytesPerSecond)
            let KBps = String(format: "%.2f", Float(bytesPerSecond / 1000))
            self.uploadProgressLabel.text = "\(progress)% (\(KBps) KBps) (\(estimatedTime) sec remain)"
        }
    }
}

//******************************************************************************
// MARK: CBCentralManagerDelegate
//******************************************************************************

extension ViewController: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // TODO: implement
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String? else {
            return
        }
        guard self.name == name else {
            return
        }
        print("Stopping scan...")
        centralManager.stopScan()
        
        // Update the UI on connection state changes
        setupPeripheral(peripheral)
    }
}

//******************************************************************************
// MARK: ConnectionObserver
//******************************************************************************

extension ViewController: ConnectionStateObserver {
    
    func peripheral(_ transport: McuMgrTransport, didChangeStateTo state: CBPeripheralState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectionStateLabel.text = "Connected"
                break
            case .connecting:
                self.connectionStateLabel.text = "Connecting..."
                break
            case .disconnecting:
                self.connectionStateLabel.text = "Disconnecting..."
                break
            case .disconnected:
                self.connectionStateLabel.text = "Disconnected"
                break
            }
        }
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
        guard let transport = transport else {
            return
        }
        addressLabel.text = transport.identifier.uuidString
        nameLabel.text = transport.name ?? "Unknown"
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
            hashLabel0.text = Data(imageSlot0.hash).hexEncodedString(options: .upperCase)
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
            hashLabel1.text = Data(imageSlot1.hash).hexEncodedString(options: .upperCase)
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
