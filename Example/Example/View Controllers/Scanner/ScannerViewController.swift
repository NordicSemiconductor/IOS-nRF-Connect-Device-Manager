/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import CoreBluetooth
import iOSMcuManagerLibrary

// MARK: - ScannerViewController

final class ScannerViewController: UITableViewController, CBCentralManagerDelegate, UIPopoverPresentationControllerDelegate, ScannerFilterDelegate {
    
    // MARK: @IBOutlet(s)
    
    @IBOutlet weak var emptyPeripheralsView: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    // MARK: Private Properties
    
    private var pullToRefreshControl: UIRefreshControl!
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals = [DiscoveredPeripheral]()
    private var filteredPeripherals = [DiscoveredPeripheral]()
    
    private var filterByName: Bool!
    private var filterByRssi: Bool!
    
    // MARK: @IBAction
    
    @IBAction func aboutTapped(_ sender: UIBarButtonItem) {
        let rootViewController = navigationController as? RootViewController
        rootViewController?.showIntro(animated: true)
    }
    
    // MARK: UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        centralManager = CBCentralManager()
        centralManager.delegate = self
        
        // Default to true to filter devices by name
        filterByName = UserDefaults.standard.object(forKey: "filterByName") != nil ? UserDefaults.standard.bool(forKey: "filterByName") : true
        filterByRssi = UserDefaults.standard.bool(forKey: "filterByRssi")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        discoveredPeripherals.removeAll()
        tableView.reloadData()
        
        guard pullToRefreshControl == nil else { return }
        pullToRefreshControl = UIRefreshControl()
        pullToRefreshControl.addTarget(self, action: #selector(onPullToRefresh(_:)), for: .valueChanged)
        tableView.refreshControl = pullToRefreshControl
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if centralManager.state == .poweredOn {
            startScanner()
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
    
    // MARK: Segue control
    
    private enum Segue: String {
        case showFilter, connect
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let identifier = segue.identifier!
        guard let selectedSegue = Segue(rawValue: identifier) else { return }
        switch selectedSegue {
        case .showFilter:
            let filterController = segue.destination as! ScannerFilterViewController
            filterController.popoverPresentationController?.delegate = self
            filterController.filterByNameEnabled = filterByName
            filterController.filterByRssiEnabled = filterByRssi
            filterController.delegate = self
        case .connect:
            let controller = segue.destination as! BaseViewController
            controller.peripheral = (sender as! DiscoveredPeripheral)
        }
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        // This will force the Filter ViewController
        // to be displayed as a popover on iPhones.
        return .none
    }
    
    // MARK: Pull-to-refresh
    
    @objc private func onPullToRefresh(_ sender: Any?) {
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        discoveredPeripherals.removeAll()
        filteredPeripherals.removeAll()
        tableView.reloadData()
        pullToRefreshControl.endRefreshing()
        startScanner()
    }
    
    // MARK: Filter delegate
    
    func filterSettingsDidChange(filterByName: Bool, filterByRssi: Bool) {
        self.filterByName = filterByName
        self.filterByRssi = filterByRssi
        UserDefaults.standard.set(filterByName, forKey: "filterByName")
        UserDefaults.standard.set(filterByRssi, forKey: "filterByRssi")
        
        filteredPeripherals.removeAll()
        for peripheral in discoveredPeripherals {
            if matchesFilters(peripheral) {
                filteredPeripherals.append(peripheral)
            }
        }
        tableView.reloadData()
    }
    
    // MARK: Table view data source
    
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
        
        performSegue(withIdentifier: Segue.connect.rawValue,
                     sender: filteredPeripherals[indexPath.row])
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return "   Scanner"
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return "   ⓘ You can Pull-to-refresh this list."
    }
    
    // MARK: CBCentralManagerDelegate
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Find peripheral among already discovered ones, or create a new
        // object if it is a new one.
        var discoveredPeripheral: DiscoveredPeripheral! = discoveredPeripherals.first(where: {
            $0.basePeripheral.identifier == peripheral.identifier
        })
        if discoveredPeripheral == nil {
            discoveredPeripheral = DiscoveredPeripheral(peripheral)
            discoveredPeripherals.append(discoveredPeripheral)
        }
        
        // Update the object with new values.
        discoveredPeripheral.update(withAdvertisementData: advertisementData, andRSSI: RSSI)
        
        // If the device is already on the filtered list, update it.
        // It will be shown even if the advertising packet is no longer
        // matching the filter. We don't want any blinking on the device list.
        if let index = filteredPeripherals.firstIndex(of: discoveredPeripheral) {
            // Update the cell views directly, without refreshing the
            // whole table.
            if let cell = tableView.cellForRow(at: [0, index]) as? ScannerTableViewCell {
                cell.peripheralUpdatedAdvertisementData(discoveredPeripheral)
            }
        } else {
            // Check if the peripheral matches the current filters.
            if matchesFilters(discoveredPeripheral) {
                filteredPeripherals.append(discoveredPeripheral)
                tableView.reloadData()
            }
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            print("Central is not powered on")
            activityIndicator.stopAnimating()
        } else {
            startScanner()
        }
    }
    
    // MARK: Private helper methods
    
    private func startScanner() {
        activityIndicator.startAnimating()
        let hidService: CBUUID! = CBUUID(string: "1812")
        let defaultTransportConfiguration = DefaultTransportConfiguration()
        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [defaultTransportConfiguration.serviceUUID, hidService])
        for peripheral in connectedPeripherals {
            var advertisementData = [String: Any]()
            advertisementData[CBAdvertisementDataLocalNameKey] = peripheral.name ?? ""
            centralManager(centralManager, didDiscover: peripheral, advertisementData: advertisementData, rssi: -127)
        }
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
    }
    
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
        // Filter by name if the name filter switch is on
        if filterByName {
            // Only show devices with a name (not "N/A" or empty)
            if discoveredPeripheral.advertisedName.isEmpty || discoveredPeripheral.advertisedName == "N/A" {
                return false
            }
        }
        if filterByRssi && discoveredPeripheral.highestRSSI.decimalValue < -50 {
            return false
        }
        return true
    }
}
