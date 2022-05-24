//
//  McuMgrBleTransportWriteState.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 12/5/22.
//

import Foundation
import Dispatch

// MARK: - McuMgrBleTransportWrite

typealias McuMgrBleTransportWrite = (sequenceNumber: UInt8, writeLock: ResultLock, chunk: Data?, totalChunkSize: Int?)

// MARK: - McuMgrBleTransportWriteState

final class McuMgrBleTransportWriteState {
    
    // MARK: - Private Properties
    
    private let lockingQueue = DispatchQueue(label: "McuMgrBleTransportWriteState")
    
    private var state = [UInt8: McuMgrBleTransportWrite]()
    
    // MARK: - APIs
    
    subscript(sequenceNumber: UInt8) -> McuMgrBleTransportWrite? {
        get {
            lockingQueue.sync { state[sequenceNumber] }
        }
    }
    
    func newWrite(sequenceNumber: UInt8, lock: ResultLock) {
        lockingQueue.async {
            self.state[sequenceNumber] = (sequenceNumber: sequenceNumber, writeLock: lock, nil, nil)
        }
    }
    
    func received(sequenceNumber: UInt8, data: Data) {
        lockingQueue.async {
            if  self.state[sequenceNumber]?.chunk == nil {
                // If we do not have any current response data, this is the initial
                // packet in a potentially fragmented response. Get the expected
                // length of the full response and initialize the responseData with
                // the expected capacity.
                guard let dataSize = McuMgrResponse.getExpectedLength(scheme: .ble, responseData: data) else {
                    self.state[sequenceNumber]?.writeLock.open(McuMgrTransportError.badResponse)
                    return
                }
                self.state[sequenceNumber]?.chunk = Data(capacity: dataSize)
                self.state[sequenceNumber]?.totalChunkSize = dataSize
            }
            
            self.state[sequenceNumber]?.chunk?.append(data)
            
            guard let chunk = self.state[sequenceNumber]?.chunk,
                  let expectedChunkSize = self.state[sequenceNumber]?.totalChunkSize,
                  chunk.count >= expectedChunkSize else { return }
            
            self.state[sequenceNumber]?.writeLock.open()
        }
    }
    
    func completedWrite(sequenceNumber: UInt8) {
        lockingQueue.async {
            self.state[sequenceNumber] = nil
        }
    }
    
    func onError(_ error: Error) {
        lockingQueue.async {
            self.state.forEach { _, value in
                value.writeLock.open(error)
            }
        }
    }
    
    func onWriteError(sequenceNumber: UInt8, error: Error) {
        lockingQueue.async {
            self.state[sequenceNumber]?.writeLock.open(error)
        }
    }
}
