/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import McuManager

class FileDownloadViewController: UIViewController, McuMgrViewController {

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
        let recents = (UserDefaults.standard.array(forKey: "recents") ?? []) as! [String]
        
        let alert = UIAlertController(title: "Recents", message: nil, preferredStyle: .actionSheet)
        let action: (UIAlertAction) -> Void = { action in
            self.file.text = action.title!
            self.refreshSource()
        }
        recents.forEach { name in
            alert.addAction(UIAlertAction(title: name, style: .default, handler: action))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    @IBAction func download(_ sender: UIButton) {
        if file.text!.count > 0 {
            addRecent(file.text!)
            _ = fsManager.download(name: source.text!, delegate: self)
        }
    }
    
    private var fsManager: FileSystemManager!
    var transporter: McuMgrTransport! {
        didSet {
            fsManager = FileSystemManager(transporter: transporter)
        }
    }
    var partition: String = "nffs" {
        didSet {
            refreshSource()
        }
    }
    var height: CGFloat = 80
    var tableView: UITableView!

    private func refreshSource() {
        source.text = "/\(partition)/\(file.text!)"
    }
    
    override func viewDidLoad() {
        let recents = UserDefaults.standard.array(forKey: "recents")
        actionOpenRecents.isEnabled = recents != nil
    }
    
    func addRecent(_ name: String) {
        var recents = (UserDefaults.standard.array(forKey: "recents") ?? []) as! [String]
        if !recents.contains(where: { $0 == name }) {
            recents.append(name)
        }
        UserDefaults.standard.set(recents, forKey: "recents")
        actionOpenRecents.isEnabled = true
    }
}

extension FileDownloadViewController: FileDownloadDelegate {
    
    func downloadProgressDidChange(bytesDownloaded: Int, fileSize: Int, timestamp: Date) {
        progress.progress = Float(bytesDownloaded) / Float(fileSize)
    }
    
    func downloadDidFail(with error: Error) {
        if let transferError = error as? FileTransferError {
            switch transferError {
            case .mcuMgrErrorCode(.unknown):
                fileName.textColor = UIColor.darkGray
                fileName.text = "File not found"
            default:
                fileName.textColor = UIColor.red
                fileName.text = "\(error)"
                break
            }
        } else {
            fileName.textColor = UIColor.red
            fileName.text = "\(error)"
        }
        fileContent.text = nil
        progress.setProgress(0, animated: true)
        
        height = 146
        tableView.reloadData()
    }
    
    func downloadDidCancel() {
        progress.setProgress(0, animated: true)
    }
    
    func download(of name: String, didFinish data: Data) {
        fileName.textColor = UIColor.darkGray
        fileName.text = "\(name) (\(data.count) bytes)"
        fileContent.text = String(data: data, encoding: .utf8)
        progress.setProgress(0, animated: false)
        
        let bounds = CGSize(width: fileContent.frame.width, height: CGFloat.greatestFiniteMagnitude)
        let rect = fileContent.sizeThatFits(bounds)
        height = 146 + rect.height
        tableView.reloadData()
    }
}
