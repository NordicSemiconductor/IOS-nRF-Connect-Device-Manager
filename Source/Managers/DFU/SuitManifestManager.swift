//
//  SuitManifestManager.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 29/5/24.
//

import Foundation

// MARK: - FirmwareUpgradeManager

public class SuitManifestManager {
    
    // MARK: Properties
    
    private let suitManager: SuitManager
    private var callback: ManifestCallback?
    private var roleIndex: Int?
    private var roles: [McuMgrManifestListResponse.Manifest.Role]
    private var responses: [McuMgrManifestStateResponse]
    public weak var logDelegate: McuMgrLogDelegate?
    
    // MARK: Init
    
    public init(transporter: McuMgrTransport) {
        self.suitManager = SuitManager(transporter: transporter)
        self.roles = []
        self.responses = []
    }
    
    // MARK: API
    
    public typealias ManifestCallback = ([McuMgrManifestStateResponse], Error?) -> Void
    public func listManifest(callback: @escaping ManifestCallback) {
        self.callback = callback
        roleIndex = 0
        roles = []
        responses = []
        listManifests()
    }
    
    public func provide(_ resource: FirmwareUpgradeManager.Resource) {
        // TODO: Work In Progress.
    }
    
    // MARK: Private
    
    private func listManifests() {
        self.logDelegate?.log("Requesting List of Manifests...", ofCategory: .suit,
                              atLevel: .verbose)
        suitManager.listManifests(callback: listManifestCallback)
    }
    
    private func validateNext() {
        guard let i = roleIndex else { return }
        if i < roles.count {
            let role = roles[i]
            logDelegate?.log("Sending Manifest State command for Role \(role.description)", ofCategory: .suit,
                                  atLevel: .verbose)
            suitManager.getManifestState(for: role, callback: roleStateCallback)
        } else {
            callback?(responses, nil)
        }
    }
    
    // MARK: List Manifest Callback
    
    private lazy var listManifestCallback: McuMgrCallback<McuMgrManifestListResponse> = { [weak self] response, error in
        guard let self else { return }
        
        guard error == nil, let response, response.rc != 8 else {
            self.logDelegate?.log("List Manifest Callback not Supported.", ofCategory: .suit, atLevel: .error)
            self.callback?([], error)
            return
        }
        
        let roles = response.manifests.compactMap(\.role)
        self.roleIndex = 0
        self.roles = roles
        if #available(iOS 13.0, *) {
            let rolesList = ListFormatter.localizedString(byJoining: roles.map(\.description))
            self.logDelegate?.log("Received Response with Roles: \(rolesList)", ofCategory: .suit, atLevel: .debug)
        }
        self.validateNext()
    }
    
    // MARK: Role State Callback
    
    private lazy var roleStateCallback: McuMgrCallback<McuMgrManifestStateResponse> = { [weak self] response, error in
        guard let self else { return }
        guard error == nil, let response, response.rc != 8 else {
            self.logDelegate?.log("List Manifest Callback not Supported.", ofCategory: .suit, atLevel: .error)
            return
        }
        self.responses.append(response)
        self.roleIndex? += 1
        self.validateNext()
    }
}
