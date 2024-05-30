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
    
    private var offset: UInt64 = 0
    private var envelopeData: Data?
    private weak var uploadDelegate: (any ImageUploadDelegate)?
    
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
    
    public func upload(_ data: Data, delegate: ImageUploadDelegate?) {
        offset = 0
        envelopeData = data
        uploadDelegate = delegate
        upload(data, at: offset)
    }
    
    private func upload(_ data: Data, at offset: UInt64) {
        let payloadLength = maxDataPacketLengthFor(data: data, offset: offset)
        
        let chunkOffset = offset
        let chunkEnd = min(chunkOffset + payloadLength, UInt64(data.count))
        var payload: [String:CBOR] = ["data": CBOR.byteString([UInt8](data[chunkOffset..<chunkEnd])),
                                      "off": CBOR.unsignedInt(chunkOffset)]
        let uploadTimeoutInSeconds: Int
        if chunkOffset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt64(data.count)), forKey: "len")
            // When uploading offset 0, we might trigger an erase on the firmware's end.
            // Hence, the longer timeout.
            uploadTimeoutInSeconds = McuManager.DEFAULT_SEND_TIMEOUT_SECONDS
        } else {
            uploadTimeoutInSeconds = McuManager.FAST_TIMEOUT
        }
        send(op: .write, commandId: SuitID.envelopeUpload, payload: payload,
             timeout: uploadTimeoutInSeconds, callback: uploadCallback)
    }
    
    // MARK: uploadCallback
    
    private lazy var uploadCallback: McuMgrCallback<McuMgrUploadResponse> = { [weak self] response, error in
        guard let self else { return }
        
        guard let envelopeData else {
            self.uploadDelegate?.uploadDidFail(with: ImageUploadError.invalidData)
            return
        }
        
        // Check for an error.
        if let error {
            if case let McuMgrTransportError.insufficientMtu(newMtu) = error {
                do {
                    try self.setMtu(newMtu)
                    self.upload(envelopeData, at: 0)
                    
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
            self.uploadDelegate?.uploadProgressDidChange(bytesSent: Int(offset), imageSize: envelopeData.count, timestamp: Date())
            if offset < envelopeData.count {
                self.upload(envelopeData, at: offset)
            } else {
                // Assume success
                self.uploadDelegate?.uploadDidFinish()
            }
        }
    }
    
    // MARK: Packet Calculation
    
    private func maxDataPacketLengthFor(data: Data,  offset: UInt64) -> UInt64 {
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
        // If this is the initial packet we have to include the length of the
        // entire image.
        if offset == 0 {
            payload.updateValue(CBOR.unsignedInt(UInt64(data.count)), forKey: "len")
        }
        // Build the packet and return the size.
        let packet = McuManager.buildPacket(scheme: transporter.getScheme(), version: .SMPv2, op: .write,
                                            flags: 0, group: group.rawValue, sequenceNumber: 0,
                                            commandId: SuitID.envelopeUpload, payload: payload)
        var packetOverhead = packet.count + 5
        if transporter.getScheme().isCoap() {
            // Add 25 bytes to packet overhead estimate for the CoAP header.
            packetOverhead = packetOverhead + 25
        }
        return packetOverhead
    }
}
