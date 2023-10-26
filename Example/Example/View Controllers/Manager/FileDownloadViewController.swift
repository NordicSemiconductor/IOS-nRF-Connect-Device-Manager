/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

class FileDownloadViewController: UIViewController, McuMgrViewController {
    
    private let recentsKey = "recents"

    @IBOutlet weak var file: UITextField!
    @IBOutlet weak var actionOpenRecents: UIButton!
    @IBOutlet weak var actionDownload: UIButton!
    @IBOutlet weak var source: UILabel!
    @IBOutlet weak var progress: UIProgressView!
    @IBOutlet weak var fileName: UILabel!
    @IBOutlet weak var fileContent: UILabel!
    
    @IBAction func nameChanged(_ sender: UITextField) {
        refreshSource()
    }
    @IBAction func openRecents(_ sender: UIButton) {
        let recents = (UserDefaults.standard.array(forKey: recentsKey) ?? []) as! [String]
        
        let alert = UIAlertController(title: "Recents", message: nil, preferredStyle: .actionSheet)
        let action: (UIAlertAction) -> Void = { action in
            self.file.text = action.title!
            self.file.becomeFirstResponder()
            self.refreshSource()
        }
        recents.forEach { name in
            alert.addAction(UIAlertAction(title: name, style: .default, handler: action))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = sender
        present(alert, animated: true)
    }
    @IBAction func download(_ sender: Any) {
        file.resignFirstResponder()
        if !file.text!.isEmpty {
            addRecent(file.text!)
            _ = fsManager.download(name: source.text!, delegate: self)
        }
    }
    
    var transporter: McuMgrTransport! {
        didSet {
            fsManager = FileSystemManager(transporter: transporter)
            fsManager.logDelegate = UIApplication.shared.delegate as? McuMgrLogDelegate
        }
    }
    
    private var fsManager: FileSystemManager!
    private var partition: String {
        return UserDefaults.standard
            .string(forKey: FilesController.partitionKey)
            ?? FilesController.defaultPartition
    }

    private func refreshSource() {
        source.text = "/\(partition)/\(file.text!)"
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let recents = UserDefaults.standard.array(forKey: recentsKey)
        actionOpenRecents.isEnabled = recents != nil
        view.translatesAutoresizingMaskIntoConstraints = false
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        refreshSource()
    }
    
    func addRecent(_ name: String) {
        var recents = (UserDefaults.standard.array(forKey: recentsKey) ?? []) as! [String]
        if !recents.contains(where: { $0 == name }) {
            recents.append(name)
        }
        UserDefaults.standard.set(recents, forKey: recentsKey)
        actionOpenRecents.isEnabled = true
    }
}

extension FileDownloadViewController: FileDownloadDelegate {
    
    func downloadProgressDidChange(bytesDownloaded: Int, fileSize: Int, timestamp: Date) {
        progress.progress = Float(bytesDownloaded) / Float(fileSize)
    }
    
    func downloadDidFail(with error: Error) {
        fileName.textColor = .systemRed
        switch error as? FileTransferError {
        // TODO: Fix by attempting to check specific Errors from FilesystemError.
//        case .mcuMgrErrorCode(.unknown):
//            fileName.text = "File not found"
        default:
            fileName.text = error.localizedDescription
        }
        fileContent.text = nil
        progress.setProgress(0, animated: true)
        
        (parent as! FilesController).innerViewReloaded()
    }
    
    func downloadDidCancel() {
        progress.setProgress(0, animated: true)
    }
    
    func download(of name: String, didFinish data: Data) {
        fileName.textColor = .primary
        fileName.text = "\(name) (\(data.count) bytes)"
        fileContent.text = String(data: data, encoding: .utf8)
        progress.setProgress(0, animated: false)
        
        (parent as! FilesController).innerViewReloaded()
    }
}
