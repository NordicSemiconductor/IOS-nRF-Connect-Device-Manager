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
        send(op: .write, commandId: ID.Reset.rawValue, payload: [:], callback: callback)
    }
}
