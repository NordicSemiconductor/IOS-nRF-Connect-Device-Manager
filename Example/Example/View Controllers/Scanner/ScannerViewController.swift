/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import CoreBluetooth
import iOSMcuManagerLibrary

class ScannerViewController: UITableViewController, CBCentralManagerDelegate, UIPopoverPresentationControllerDelegate, ScannerFilterDelegate {
    
    @IBOutlet weak var emptyPeripheralsView: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals = [DiscoveredPeripheral]()
    private var filteredPeripherals = [DiscoveredPeripheral]()
    
    private var filterByUuid: Bool!
    private var filterByRssi: Bool!
    
    @IBAction func aboutTapped(_ sender: UIBarButtonItem) {
        let rootViewController = navigationController as? RootViewController
        rootViewController?.showIntro(animated: true)
    }
    
    // MARK: - UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()
        centralManager = CBCentralManager()
        centralManager.delegate = self
        
        filterByUuid = UserDefaults.standard.bool(forKey: "filterByUuid")
        filterByRssi = UserDefaults.standard.bool(forKey: "filterByRssi")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        discoveredPeripherals.removeAll()
        tableView.reloadData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if centralManager.state == .poweredOn {
            activityIndicator.startAnimating()
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if view.subviews.contains(emptyPeripheralsView) {
            coordinator.animate(alongsideTransition: { (context) in
                let width = self.emptyPeripheralsView.frame.size.width
                let height = self.emptyPeripheralsView.frame.size.height
                if context.containerView.frame.size.height > context.containerView.frame.size.width {
                    self.emptyPeripheralsView.frame = CGRect(x: 0,
                                                             y: (context.containerView.frame.size.height / 2) - (height / 2),
                                                             width: width,
                                                             height: height)
                } else {
                    self.emptyPeripheralsView.frame = CGRect(x: 0,
                                                             y: 16,
                                                             width: width,
                                                             height: height)
                }
            })
        }
    }
    
    // MARK: - Segue control
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let identifier = segue.identifier!
        switch identifier {
        case "showFilter":
            let filterController = segue.destination as! ScannerFilterViewController
            filterController.popoverPresentationController?.delegate = self
            filterController.filterByUuidEnabled = filterByUuid
            filterController.filterByRssiEnabled = filterByRssi
            filterController.delegate = self
        case "connect":
            let controller = segue.destination as! BaseViewController
            controller.peripheral = (sender as! DiscoveredPeripheral)
        default:
            break
        }
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        // This will force the Filter ViewController
        // to be displayed as a popover on iPhones.
        return .none
    }
    
    // MARK: - Filter delegate
    func filterSettingsDidChange(filterByUuid: Bool, filterByRssi: Bool) {
        self.filterByUuid = filterByUuid
        self.filterByRssi = filterByRssi
        UserDefaults.standard.set(filterByUuid, forKey: "filterByUuid")
        UserDefaults.standard.set(filterByRssi, forKey: "filterByRssi")
        
        filteredPeripherals.removeAll()
        for peripheral in discoveredPeripherals {
            if matchesFilters(peripheral) {
                filteredPeripherals.append(peripheral)
            }
        }
        tableView.reloadData()
    }
    
    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if filteredPeripherals.count > 0 {
            hideEmptyPeripheralsView()
        } else {
            showEmptyPeripheralsView()
        }
        return filteredPeripherals.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let aCell = tableView.dequeueReusableCell(withIdentifier: ScannerTableViewCell.reuseIdentifier, for: indexPath) as! ScannerTableViewCell
        aCell.setupViewWithPeripheral(filteredPeripherals[indexPath.row])
        return aCell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        centralManager.stopScan()
        activityIndicator.stopAnimating()
        
        performSegue(withIdentifier: "connect", sender: filteredPeripherals[indexPath.row])
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Find peripheral among already discovered ones, or create a new
        // object if it is a new one.
        var discoveredPeripheral = discoveredPeripherals.first(where: { $0.basePeripheral.identifier == peripheral.identifier })
        if discoveredPeripheral == nil {
            discoveredPeripheral = DiscoveredPeripheral(peripheral)
            discoveredPeripherals.append(discoveredPeripheral!)
        }
        
        // Update the object with new values.
        discoveredPeripheral!.update(withAdvertisementData: advertisementData, andRSSI: RSSI)
        
        // If the device is already on the filtered list, update it.
        // It will be shown even if the advertising packet is no longer
        // matching the filter. We don't want any blinking on the device list.
        if let index = filteredPeripherals.firstIndex(of: discoveredPeripheral!) {
            // Update the cell views directly, without refreshing the
            // whole table.
            if let aCell = tableView.cellForRow(at: [0, index]) as? ScannerTableViewCell {
                aCell.peripheralUpdatedAdvertisementData(discoveredPeripheral!)
            }
        } else {
            // Check if the peripheral matches the current filters.
            if matchesFilters(discoveredPeripheral!) {
                filteredPeripherals.append(discoveredPeripheral!)
                tableView.reloadData()
            }
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            print("Central is not powered on")
            activityIndicator.stopAnimating()
        } else {
            activityIndicator.startAnimating()
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        }
    }
    
    // MARK: - Private helper methods
    
    /// Shows the No Peripherals view.
    private func showEmptyPeripheralsView() {
        if !view.subviews.contains(emptyPeripheralsView) {
            view.addSubview(emptyPeripheralsView)
            emptyPeripheralsView.alpha = 0
            emptyPeripheralsView.frame = CGRect(x: 0,
                                                y: (view.frame.height / 2) - (emptyPeripheralsView.frame.size.height / 2),
                                                width: view.frame.width,
                                                height: emptyPeripheralsView.frame.height)
            view.bringSubviewToFront(emptyPeripheralsView)
            UIView.animate(withDuration: 0.5, animations: {
                self.emptyPeripheralsView.alpha = 1
            })
        }
    }
    
    /// Hides the No Peripherals view. This method should be
    /// called when a first peripheral was found.
    private func hideEmptyPeripheralsView() {
        if view.subviews.contains(emptyPeripheralsView) {
            UIView.animate(withDuration: 0.5, animations: {
                self.emptyPeripheralsView.alpha = 0
            }, completion: { (completed) in
                self.emptyPeripheralsView.removeFromSuperview()
            })
        }
    }
    
    /// Returns true if the discovered peripheral matches
    /// current filter settings.
    ///
    /// - parameter discoveredPeripheral: A peripheral to check.
    /// - returns: True, if the peripheral matches the filter,
    ///   false otherwise.
    private func matchesFilters(_ discoveredPeripheral: DiscoveredPeripheral) -> Bool {
        if filterByUuid && discoveredPeripheral.advertisedServices?.contains(McuMgrBleTransportConstant.SMP_SERVICE) != true {
            return false
        }
        if filterByRssi && discoveredPeripheral.highestRSSI.decimalValue < -50 {
            return false
        }
        return true
    }
}
