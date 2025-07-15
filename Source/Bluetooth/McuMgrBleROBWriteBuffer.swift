//
//  McuMgrBleROBWriteBuffer.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 14/7/25.
//

import Foundation
import Dispatch
import CoreBluetooth

// MARK: - McuMgrBleROBWriteBuffer

/**
 ROB for Re-Order Buffer.
 
 The purpose of this last-level transport layer is to guarantee all chunks for the same
 sequence number are sent in-order. If multiple pieces (chunks) of different sequence
 numbers are interleaved, it'll garble up the results and the firmware will not be able to
 understand anything.
 */
internal final class McuMgrBleROBWriteBuffer {
    
    // MARK: - Private Properties
    
    private let lock = DispatchQueue(label: "McuMgrBleROBWriteBuffer", qos: .userInitiated)
    
    private var pausedWritesWithoutResponse: Bool
    private var window: [Write]
    
    private weak var log: McuMgrLogDelegate?
    
    // MARK: init
    
    init(_ log: McuMgrLogDelegate?) {
        self.log = log
        self.pausedWritesWithoutResponse = false
        self.window = [Write]()
    }
    
    // MARK: API
    
    internal func isInFlight(_ sequenceNumber: McuSequenceNumber) -> Bool {
        lock.sync { [unowned self] in
            return window.contains(where: {
                $0.sequenceNumber == sequenceNumber
            })
        }
    }
    
    /**
     All chunks of the same packet need to be sent together. Otherwise, they can't be merged properly on the receiving end.
     */
    internal func enqueue(_ sequenceNumber: McuSequenceNumber, data: [Data], to peripheral: CBPeripheral, characteristic: CBCharacteristic, callback: @escaping (Data?, McuMgrTransportError?) -> Void) {
        guard !isInFlight(sequenceNumber) else {
            // Do not enqueue again if said sequence number is in-flight.
            guard pausedWritesWithoutResponse else { return }
            // Note that sometimes we will not get a "peripheralIsReadyForWriteWithoutResponse".
            // The only way to move forward, is just to ask / try again to send.
            pausedWritesWithoutResponse = false
            let targetSequenceNumber: McuSequenceNumber! = window.first?.sequenceNumber
            log(msg: "→ Continue [Seq. No: \(targetSequenceNumber)].", atLevel: .debug)
            unsafe_fulfillEnqueuedWrites(to: peripheral, for: targetSequenceNumber)
            return
        }
        
        // This lock guarantees parallel writes are not interleaved with each other.
        lock.async { [unowned self] in
            window.append(contentsOf: Write.split(sequenceNumber: sequenceNumber, chunks: data, peripheral: peripheral, characteristic: characteristic, callback: callback))
            window.sort(by: <)
            
            let targetSequenceNumber: McuSequenceNumber! = window.first?.sequenceNumber
            unsafe_fulfillEnqueuedWrites(to: peripheral, for: targetSequenceNumber)
        }
    }
    
    internal func peripheralReadyToWrite(_ peripheral: CBPeripheral) {
        lock.async { [unowned self] in
            // Note: peripheralIsReady(toSendWriteWithoutResponse:) is called many times.
            // We only want to continue past this guard when a write was paused and
            // thus added to `pausedWrites`.
            guard pausedWritesWithoutResponse else { return }
            pausedWritesWithoutResponse = false
            // Paused writes are never removed from the queue. So all we have to do is
            // restart from the front of the queue.
            let resumeWrite: Write! = window.first
            log(msg: "► [Seq: \(resumeWrite.sequenceNumber), Chk: \(resumeWrite.chunkIndex)] Resume (Peripheral Ready for Write Without Response)", atLevel: .debug)
            unsafe_fulfillEnqueuedWrites(to: peripheral, for: resumeWrite.sequenceNumber)
        }
    }
}
    
// MARK: - Private

private extension McuMgrBleROBWriteBuffer {
    
    func unsafe_fulfillEnqueuedWrites(to peripheral: CBPeripheral, for sequenceNumber: McuSequenceNumber) {
        for write in window where write.sequenceNumber == sequenceNumber {
            guard peripheral.canSendWriteWithoutResponse else {
                log(msg: "⏸︎ [Seq: \(sequenceNumber), Chk: \(write.chunkIndex)] Paused (Peripheral not Ready for Write Without Response)", atLevel: .debug)
                pausedWritesWithoutResponse = true
                return
            }
            
            if write.chunkIndex == 0 {
                for (i, write) in window.enumerated() where write.sequenceNumber == sequenceNumber {
                    #if DEBUG
                    print("✈ [Seq: \(sequenceNumber), Chk: \(write.chunkIndex)]")
                    #endif
                    window[i].inFlight = true
                }
            }
            
            peripheral.writeValue(write.chunk, for: write.characteristic,
                                  type: .withoutResponse)
            write.callback(write.chunk, nil)
            let i: Int! = window.firstIndex(of: write)
            window.remove(at: i)
        }
    }
    
    func log(msg: @autoclosure () -> String, atLevel level: McuMgrLogLevel) {
        log?.log(msg(), ofCategory: .transport, atLevel: level)
    }
}

// MARK: - Write

internal extension McuMgrBleROBWriteBuffer {
    
    struct Write {
        
        let sequenceNumber: McuSequenceNumber
        let chunkIndex: Int
        let chunk: Data
        let peripheral: CBPeripheral
        let characteristic: CBCharacteristic
        let callback: (Data?, McuMgrTransportError?) -> Void
        var inFlight: Bool
        
        init(sequenceNumber: McuSequenceNumber, chunkIndex: Int, chunk: Data, peripheral: CBPeripheral, characteristic: CBCharacteristic, callback: @escaping (Data?, McuMgrTransportError?) -> Void) {
            self.sequenceNumber = sequenceNumber
            self.chunkIndex = chunkIndex
            self.chunk = chunk
            self.peripheral = peripheral
            self.characteristic = characteristic
            self.callback = callback
            self.inFlight = false
        }
        
        static func split(sequenceNumber: McuSequenceNumber, chunks: [Data], peripheral: CBPeripheral, characteristic: CBCharacteristic, callback: @escaping (Data?, McuMgrTransportError?) -> Void) -> [Self] {
            return chunks.indices.map { i in
                Self(sequenceNumber: sequenceNumber, chunkIndex: i, chunk: chunks[i], peripheral: peripheral, characteristic: characteristic, callback: callback)
            }
        }
    }
}

// MARK: Comparable

extension McuMgrBleROBWriteBuffer.Write: Comparable {
    
    /**
     "In-flight" writes are higher priority within a given sequence number, since
     the previous sequence number might've not completed its 'write' on resume.
     If we reorder and switch to a different 'chunk' because of a retry operation,
     the end result is a reassembly packet the firmware cannot reassemble.
     */
    static func < (lhs: Self, rhs: Self) -> Bool {
        guard lhs.inFlight == rhs.inFlight else {
            // Whoever is "in-flight" wins
            return lhs.inFlight
        }
        
        if lhs.sequenceNumber == rhs.sequenceNumber {
            return lhs.chunkIndex < rhs.chunkIndex
        } else {
            return lhs.sequenceNumber < rhs.sequenceNumber
        }
    }
}

// MARK: Equatable

extension McuMgrBleROBWriteBuffer.Write: Equatable {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.sequenceNumber == rhs.sequenceNumber
            && lhs.chunkIndex == rhs.chunkIndex
            && lhs.peripheral.identifier == rhs.peripheral.identifier
            && lhs.characteristic.uuid == rhs.characteristic.uuid
    }
}
