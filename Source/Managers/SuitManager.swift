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
    
    // MARK: Constants
    
    private static let POLLING_WINDOW_MS = 5000
    private static let POLLING_INTERVAL_MS = 150
    private static let MAX_POLL_ATTEMPTS: Int = POLLING_WINDOW_MS / POLLING_INTERVAL_MS
    
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
        case uploadResource = 4
    }
    
    // MARK: Properties
    
    private var offset: UInt64 = 0
    private var uploadData: Data?
    private var pollAttempts: Int = 0
    private var sessionID: UInt64?
    private var state: SuitManagerState = .none
    private weak var uploadDelegate: SuitManagerDelegate?
    
    private var callback: McuMgrCallback<SuitListResponse>?
    private var roleIndex: Int?
    private var roles: [McuMgrManifestListResponse.Manifest.Role] = []
    private var responses: [McuMgrManifestStateResponse] = []
    
    // MARK: Init
    
    public init(transport: McuMgrTransport) {
        super.init(group: McuMgrGroup.suit, transport: transport)
    }
    
    // MARK: List
    
    /**
     Command allows to get information about roles of manifests supported by the device.
     */
    public func listManifest(callback: @escaping McuMgrCallback<SuitListResponse>) {
        self.callback = callback
        roleIndex = 0
        roles = []
        responses = []
        send(op: .read, commandId: SuitID.manifestList, payload: nil, 
             callback: listManifestCallback)
    }
    
    private func validateNext() {
        guard let i = roleIndex else { return }
        if i < roles.count {
            let role = roles[i]
            logDelegate?.log("Sending Manifest State command for Role \(role.description)",
                             ofCategory: .suit, atLevel: .verbose)
            getManifestState(for: role, callback: roleStateCallback)
        } else {
            let mandatoryHeaderData = McuManager.buildPacket(scheme: .ble, version: .SMPv2,
                                                             op: .read, flags: 0,
                                                             group: McuMgrGroup.suit.rawValue,
                                                             sequenceNumber: 0,
                                                             commandId: SuitID.manifestList,
                                                             payload: [:])
            let suitResponse = try? SuitListResponse(cbor: nil)
            suitResponse?.header = try? McuMgrHeader(data: mandatoryHeaderData)
            suitResponse?.states = responses
            callback?(suitResponse, nil)
        }
    }
    
    // MARK: List Manifest Callback
    
    private lazy var listManifestCallback: McuMgrCallback<McuMgrManifestListResponse> = { [weak self] response, error in
        guard let self else { return }
        
        guard error == nil, let response, response.rc != 8 else {
            self.logDelegate?.log("List Manifest Callback not Supported.", ofCategory: .suit, atLevel: .error)
            self.callback?(nil, error)
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
    
    // MARK: Poll
    
    /**
     * Poll for required image
     *
     * SUIT command sequence has the ability of conditional execution of directives, i.e. based on the digest of installed image. That opens a scenario where SUIT candidate envelope contains only SUIT manifests, images (those required to be updated) are fetched by the device only if it is necessary. In that case, the device informs the SMP client that specific image is required via callback (and this is what this command implements), and then the SMP client uploads requested image. Due to the fact that SMP is designed in client-server pattern and lack of server-sent notifications, implementation is based on polling.
     *
     * After sending the Envelope, the client should periodically poll the device to check if an image is required.
     *
     * - Parameter callback: the asynchronous callback.
     */
    public func poll(callback: @escaping McuMgrCallback<McuMgrPollResponse>) {
        send(op: .read, commandId: SuitID.pollImageState, payload: nil, callback: callback)
    }
    
    // MARK: Upload Envelope
    
    public func uploadEnvelope(_ envelopeData: Data, delegate: SuitManagerDelegate?) {
        offset = 0
        pollAttempts = 0
        uploadData = envelopeData
        uploadDelegate = delegate
        sessionID = nil
        state = .uploadingEnvelope
        upload(envelopeData, at: offset)
    }
    
    // MARK: Upload Resource
    
    public func uploadResource(_ resourceData: Data) {
        offset = 0
        pollAttempts = 0
        uploadData = resourceData
        state = .uploadingResource
        // Keep uploadDelegate AND sessionID
        upload(resourceData, at: offset)
    }
    
    private func upload(_ data: Data, at offset: UInt64) {
        let payloadLength = maxDataPacketLengthFor(data: data, offset: offset)
        
        let chunkOffset = offset
        let chunkEnd = min(chunkOffset + payloadLength, UInt64(data.count))
        var payload: [String: CBOR] = ["data": CBOR.byteString([UInt8](data[chunkOffset..<chunkEnd])),
                                      "off": CBOR.unsignedInt(chunkOffset)]
        if let sessionID {
            payload.updateValue(CBOR.unsignedInt(sessionID), forKey: "stream_session_id")
        }
        let uploadTimeoutInSeconds: Int
        if chunkOffset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt64(data.count)), forKey: "len")
            // When uploading offset 0, we might trigger an erase on the firmware's end.
            // Hence, the longer timeout.
            uploadTimeoutInSeconds = McuManager.DEFAULT_SEND_TIMEOUT_SECONDS
        } else {
            uploadTimeoutInSeconds = McuManager.FAST_TIMEOUT
        }
        let commandID: SuitID = sessionID == nil ? .envelopeUpload : .uploadResource
        send(op: .write, commandId: commandID, payload: payload,
             timeout: uploadTimeoutInSeconds, callback: uploadCallback)
    }
    
    // MARK: uploadCallback
    
    private lazy var uploadCallback: McuMgrCallback<McuMgrUploadResponse> = { [weak self] response, error in
        guard let self else { return }
        
        guard let uploadData else {
            self.uploadDelegate?.uploadDidFail(with: ImageUploadError.invalidData)
            return
        }
        
        // Check for an error.
        if let error {
            if case let McuMgrTransportError.insufficientMtu(newMtu) = error {
                do {
                    try self.setMtu(newMtu)
                    self.upload(uploadData, at: 0)
                } catch let mtuResetError {
                    self.uploadDelegate?.uploadDidFail(with: mtuResetError)
                }
                return
            }
            self.uploadDelegate?.uploadDidFail(with: error)
            return
        }
        
        guard let response else {
            self.uploadDelegate?.uploadDidFail(with: ImageUploadError.invalidPayload)
            return
        }
        
        if let error = response.getError() {
            self.uploadDelegate?.uploadDidFail(with: error)
            return
        }
        
        if let offset = response.off {
            self.uploadDelegate?.uploadProgressDidChange(bytesSent: Int(offset), imageSize: uploadData.count, timestamp: Date())
            if offset < uploadData.count {
                self.upload(uploadData, at: offset)
            } else {
                // Listen for disconnection event, which signals update is complete.
                transport.addObserver(self)
                // While waiting for disconnection, poll.
                // The Device might tell us it needs a resource.
                self.poll(callback: pollingCallback)
            }
        }
    }
    
    // MARK: pollingCallback
    
    private lazy var pollingCallback: McuMgrCallback<McuMgrPollResponse> = { [weak self] response, error in
        guard let self else { return }
        
        guard state.isInProgress else {
            // Success means firmware device disconnected, which can trigger errors.
            // So if we've considered the upload successful already, we don't care
            // about this callback.
            return
        }
        
        if let error {
            // Assume success, error is most likely due to disconnection.
            // Disconnection means firmware moved on and doesn't need anything from us.
            self.uploadDelegate?.uploadDidFinish()
        }
        
        if let response {
            guard response.rc != 8 else {
                // Not supported, so either no polling or device restarted.
                // It means success / continue.
                self.uploadDelegate?.uploadDidFinish()
                return
            }
            
            guard let resourceID = response.resourceID,
                  let resource = FirmwareUpgradeResource(resourceID),
                  let sessionID = response.sessionID else {
                guard pollAttempts < Self.MAX_POLL_ATTEMPTS else {
                    // Assume success / device doesn't require anything.
                    self.uploadDelegate?.uploadDidFinish()
                    return
                }
                
                // Empty response means 'keep waiting'. So we'll just retry.
                let waitTime: DispatchTimeInterval = .milliseconds(Self.POLLING_INTERVAL_MS)
                DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) { [unowned self] in
                    self.pollAttempts += 1
                    self.poll(callback: self.pollingCallback)
                }
                return
            }
            
            self.sessionID = sessionID
            guard self.uploadDelegate != nil else {
                self.uploadDelegate?.uploadDidFail(with: SuitManagerError.suitDelegateRequiredForResource(resource))
                return
            }
            // Stop listening for disconnection since firmware has requested a resource.
            self.transport.removeObserver(self)
            // Ask API user for the requested resource.
            self.uploadDelegate?.uploadRequestsResource(resource)
        }
    }
    
    // MARK: Packet Calculation
    
    private func maxDataPacketLengthFor(data: Data, offset: UInt64) -> UInt64 {
        guard offset < data.count else { return UInt64(McuMgrHeader.HEADER_LENGTH) }
        
        let remainingBytes = UInt64(data.count) - offset
        let packetOverhead = calculatePacketOverhead(data: data, offset: offset)
        let maxDataLength = UInt64(mtu) - UInt64(packetOverhead)
        return min(maxDataLength, remainingBytes)
    }
    
    private func calculatePacketOverhead(data: Data, offset: UInt64) -> Int {
        // Get the Mcu Manager header.
        var payload: [String:CBOR] = ["data": CBOR.byteString([UInt8]([0])),
                                      "off":  CBOR.unsignedInt(offset)]
        if let sessionID {
            payload.updateValue(CBOR.unsignedInt(sessionID), forKey: "stream_session_id")
        }
        
        // If this is the initial packet we have to include the length of the
        // entire image.
        if offset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt64(data.count)), forKey: "len")
        }
        // Build the packet and return the size.
        let packet = McuManager.buildPacket(scheme: transport.getScheme(), version: .SMPv2,
                                            op: .write, flags: 0, group: group.rawValue,
                                            sequenceNumber: 0, commandId: SuitID.envelopeUpload,
                                            payload: payload)
        var packetOverhead = packet.count + 5
        if transport.getScheme().isCoap() {
            // Add 25 bytes to packet overhead estimate for the CoAP header.
            packetOverhead = packetOverhead + 25
        }
        return packetOverhead
    }
}

// MARK: - ConnectionObserver

extension SuitManager: ConnectionObserver {
    
    public func transport(_ transport: McuMgrTransport, didChangeStateTo state: McuMgrTransportState) {
        // Disregard other states.
        guard state == .disconnected else { return }
        
        log(msg: "Device has disconnected.", atLevel: .info)
        transport.removeObserver(self)
        
        // Device disconnected when we expected it -> Success.
        self.state = .success
        // Firmware Upgrade complete.
        uploadDelegate?.uploadDidFinish()
    }
}

// MARK: SuitManagerState

enum SuitManagerState {
    case none
    case uploadingEnvelope, uploadingResource
    case success
    
    var isInProgress: Bool {
        switch self {
        case .none, .success:
            return false
        case .uploadingEnvelope, .uploadingResource:
            return true
        }
    }
}

// MARK: - SuitManagerError

public enum SuitManagerError: Error, LocalizedError {
    case suitDelegateRequiredForResource(_ resource: FirmwareUpgradeResource)
    
    public var errorDescription: String? {
        switch self {
        case .suitDelegateRequiredForResource(let resource):
            return "A \(String(describing: SuitFirmwareUpgradeDelegate.self)) delegate is required since the firmware is requesting resource \(resource.description)."
        }
    }
}

// MARK: - SuitManagerDelegate

public protocol SuitManagerDelegate: ImageUploadDelegate {
    
    /**
     In SUIT (Software Update for the Internet of Things), various resources, such as specific files, URL contents, etc. may be requested by the firmware device. When it does, this callback will be triggered.
     */
    func uploadRequestsResource(_ resource: FirmwareUpgradeResource)
}
