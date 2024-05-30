//
//  SuitManager.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 28/5/24.
//

import Foundation
import SwiftCBOR

// MARK: - SuitManager

public class SuitManager: McuManager {
    
    // MARK: TAG
    
    override class var TAG: McuMgrLogCategory { .suit }
    
    // MARK: IDs
    
    enum SuitID: UInt8 {
        /**
         Command allows to get information about roles of manifests supported by the device.
         */
        case manifestList = 0
        /**
         Command allows to get information about the configuration of supported manifests
         and selected attributes of installed manifests of specified role.
         */
        case manifestState = 1
        /**
         Command delivers a packet of a SUIT envelope to the device.
         */
        case envelopeUpload = 2
        /**
         SUIT command sequence has the ability of conditional execution of directives, i.e.
         based on the digest of installed image. That opens scenario where SUIT candidate
         envelope contains only SUIT manifests, images (those required to be updated) are
         fetched by the device only if it is necessary. In that case, the device informs the
         SMP client that specific image is required (and this is what this command
         implements), and then the SMP client delivers requested image in chunks. Due to the
         fact that SMP is designed in clients-server pattern and lack of server-sent
         notifications, implementation bases on polling.
         */
        case pollImageState = 3
        /**
         Command delivers a packet of a resource requested by the target device.
         */
        case resourceUpload = 4
    }
    
    // MARK: Init
    
    public init(transporter: McuMgrTransport) {
        super.init(group: McuMgrGroup.suit, transporter: transporter)
    }
    
    // MARK: API
    
    /**
     Command allows to get information about roles of manifests supported by the device.
     */
    public func listManifests(callback: @escaping McuMgrCallback<McuMgrManifestListResponse>) {
        send(op: .read, commandId: SuitID.manifestList, payload: nil, callback: callback)
    }
    
    /**
     Command allows to get information about the configuration of supported manifests
     and selected attributes of installed manifests of specified role (asynchronous).
     */
    public func getManifestState(for role: McuMgrManifestListResponse.Manifest.Role,
                                 callback: @escaping McuMgrCallback<McuMgrManifestStateResponse>) {
        let fixCallback: McuMgrCallback<McuMgrManifestStateResponse> = { response, error in
            callback(response, error)
        }
        
        let payload: [String:CBOR] = [
            "role": CBOR.unsignedInt(role.rawValue)
        ]
        send(op: .read, commandId: SuitID.manifestState, payload: payload,
             callback: fixCallback)
    }
}
