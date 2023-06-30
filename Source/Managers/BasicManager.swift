//
//  BasicManager.swift
//  
//
//  Created by Dinesh Harjani on 21/9/21.
//

import Foundation
import SwiftCBOR

// MARK: - BasicManager

/// Sends commands belonging to the Basic Group.
///
public class BasicManager: McuManager {
    override class var TAG: McuMgrLogCategory { .basic }
    
    // MARK: - Constants

    public static let MAX_ECHO_MESSAGE_SIZE_BYTES = 2475
    
    enum ID: UInt8 {
        case Reset = 0
    }
    
    // MARK: - Init
    
    public init(transporter: McuMgrTransport) {
        super.init(group: .basic, transporter: transporter)
    }
    
    // MARK: - Commands

    /// Erase stored Application-Level Settings from the Application Core.
    ///
    /// - parameter callback: The response callback with a ``McuMgrResponse``.
    public func eraseAppSettings(callback: @escaping McuMgrCallback<McuMgrResponse>) {
        send(op: .write, commandId: ID.Reset, payload: [:], timeout: McuManager.FAST_TIMEOUT, callback: callback)
    }
}

// MARK: - BasicManagerError

enum BasicManagerError: Hashable, Error, LocalizedError {
    
    case echoMessageOverTheLimit(_ messageSize: Int)
    
    var errorDescription: String? {
        switch self {
        case .echoMessageOverTheLimit(let messageSize):
            return "Echo Message of \(messageSize) bytes in size is over the limit of \(BasicManager.MAX_ECHO_MESSAGE_SIZE_BYTES) bytes."
        }
    }
}
