/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

// MARK: - DeviceController

class DeviceController: UITableViewController, UITextFieldDelegate {

    // MARK: IBOutlet(s)
    
    @IBOutlet weak var connectionStatus: ConnectionStateLabel!
    @IBOutlet weak var actionSend: UIButton!
    @IBOutlet weak var message: UITextField!
    @IBOutlet weak var messageSent: UILabel!
    @IBOutlet weak var messageSentBackground: UIImageView!
    @IBOutlet weak var messageReceived: UILabel!
    @IBOutlet weak var messageReceivedBackground: UIImageView!
    
    @IBAction func sendTapped(_ sender: UIButton) {
        message.resignFirstResponder()
        
        let text = message.text!
        send(message: text)
    }
    
    // MARK: Private Properties
    
    private var defaultManager: DefaultManager!
    
    // MARK: UIViewController API
    
    override func viewDidLoad() {
        message.delegate = self
        
        let sentBackground = #imageLiteral(resourceName: "bubble_sent")
            .resizableImage(withCapInsets: UIEdgeInsets(top: 17, left: 21, bottom: 17, right: 21),
                            resizingMode: .stretch)
            .withRenderingMode(.alwaysTemplate)
        messageSentBackground.image = sentBackground
        
        let receivedBackground = #imageLiteral(resourceName: "bubble_received")
            .resizableImage(withCapInsets: UIEdgeInsets(top: 17, left: 21, bottom: 17, right: 21),
                            resizingMode: .stretch)
            .withRenderingMode(.alwaysTemplate)
        messageReceivedBackground.image = receivedBackground
        
        let baseController = parent as! BaseViewController
        let transporter = baseController.transporter!
        defaultManager = DefaultManager(transporter: transporter)
        defaultManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // Set the connection status label as transport delegate.
        let bleTransporter = defaultManager.transporter as? McuMgrBleTransport
        bleTransporter?.delegate = connectionStatus
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        // Close the connection to allow other UIViewController(s) to do
        // their own thing.
        defaultManager.transporter.close()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped(actionSend)
        return true
    }
    
    // MARK: send
    
    private func send(message: String) {
        messageSent.text = message
        messageSent.isHidden = false
        messageSentBackground.isHidden = false
        messageReceived.isHidden = true
        messageReceivedBackground.isHidden = true
        
        defaultManager.echo(message, callback: sendCallback)
    }
    
    private lazy var sendCallback: McuMgrCallback<McuMgrEchoResponse> = { [weak self] (response: McuMgrEchoResponse?, error: Error?) in
        
        if let response = response {
            self?.messageReceived.text = response.response
            self?.messageReceivedBackground.tintColor = .zephyr
        }
        
        if let error = error {
            if case let McuMgrTransportError.insufficientMtu(newMtu) = error {
                // Change MTU to the recommended new value.
                do {
                    try self?.defaultManager.setMtu(newMtu)
                    // MTU Set successful and we have the text, so try again.
                    if let messageText = self?.messageSent.text {
                        self?.send(message: messageText)
                    }
                } catch McuManagerError.mtuValueHasNotchanged {
                    // If MTU value did not change, try reassembly.
                    if let messageText = self?.messageSent.text,
                       let bleTransport = self?.defaultManager.transporter as? McuMgrBleTransport,
                       !bleTransport.chunkSendDataToMtuSize {
                        bleTransport.chunkSendDataToMtuSize = true
                        self?.send(message: messageText)
                    }
                } catch let setMtuError {
                    self?.onError(setMtuError)
                }
            }
            self?.onError(error)
            return
        }
        
        self?.messageReceived.isHidden = false
        self?.messageReceivedBackground.isHidden = false
    }
    
    // MARK: onError
    
    private func onError(_ error: some Error) {
        messageReceived.text = "\(error.localizedDescription)"
        messageReceived.isHidden = false
        messageReceivedBackground.tintColor = .systemRed
        messageReceivedBackground.isHidden = false
    }
}
