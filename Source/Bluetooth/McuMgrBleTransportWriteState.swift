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
    
    private var state = [McuMgrBleTransportWrite]()
    
    // MARK: - APIs
    
    subscript(sequenceNumber: UInt8) -> McuMgrBleTransportWrite? {
        get {
            lockingQueue.sync { state.first(where: { $0.sequenceNumber == sequenceNumber }) }
        }
    }
    
    func newWrite(sequenceNumber: UInt8, lock: ResultLock) {
        lockingQueue.async {
            self.state.append((sequenceNumber: sequenceNumber, writeLock: lock, nil, nil))
        }
    }
    
    func received(sequenceNumber: UInt8, data: Data) {
        lockingQueue.async {
            guard let i = self.state.firstIndex(where: { $0.sequenceNumber == sequenceNumber }) else {
                return
            }
            
            if  self.state[i].chunk == nil {
                // If we do not have any current response data, this is the initial
                // packet in a potentially fragmented response. Get the expected
                // length of the full response and initialize the responseData with
                // the expected capacity.
                guard let dataSize = McuMgrResponse.getExpectedLength(scheme: .ble, responseData: data) else {
                    self.state[i].writeLock.open(McuMgrTransportError.badResponse)
                    return
                }
                self.state[i].chunk = Data(capacity: dataSize)
                self.state[i].totalChunkSize = dataSize
            }
            
            self.state[i].chunk?.append(data)
            
            guard let chunk = self.state[i].chunk,
                  let expectedChunkSize = self.state[i].totalChunkSize,
                  chunk.count >= expectedChunkSize else { return }
            
            self.state[i].writeLock.open()
        }
    }
    
    func completedWrite(sequenceNumber: UInt8) {
        lockingQueue.async {
            self.state.removeAll(where: { $0.sequenceNumber == sequenceNumber })
        }
    }
    
    func onError(_ error: Error) {
        lockingQueue.async {
            self.state.forEach {
                $0.writeLock.open(error)
            }
        }
    }
    
    func onWriteError(sequenceNumber: UInt8, error: Error) {
        lockingQueue.async {
            self.state.first(where: { $0.sequenceNumber == sequenceNumber })?.writeLock.open(error)
        }
    }
}
