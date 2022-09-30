//
//  McuMgrROBBuffer.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 29/9/22.
//

import Foundation
import Dispatch
import os.log

// MARK: - McuMgrROBBuffer<Key, Value>

public struct McuMgrROBBuffer<Key: Hashable & Comparable, Value> {
    
    // MARK: BufferError
    
    enum BufferError: Error {
        case invalidKey(_ key: Key)
        case noValueForKey(_ key: Key)
    }
    
    // MARK: Private
    
    private var internalQueue = DispatchQueue(label: "mcumgr.robbuffer.queue")
    
    private var pendingKeys: [Key] = []
    private var buffer: [Key: Value] = [:]
    
    // MARK: API
    
    subscript(_ key: Key) -> Value? {
        buffer[key]
    }
    
    mutating func expectingValue(for key: Key) {
        internalQueue.sync {
            pendingKeys.append(key)
        }
    }
    
    mutating func receivedInOrder(_ value: Value, for key: Key) throws -> Bool {
        try internalQueue.sync {
            guard let i = pendingKeys.firstIndex(where: { $0 == key }) else {
                throw BufferError.invalidKey(key)
            }
            
            assert(pendingKeys[i] == key)
            buffer[key] = value

            let valueReceivedInOrder = i == 0
            if valueReceivedInOrder {
                pendingKeys.removeFirst()
            } else {
                pendingKeys.remove(at: i)
                if #available(iOS 10.0, *) {
                    os_log("%{public}@", log: .default, type: .info, "Received key \(key) OoO (Out of Order).")
                }
            }
            return valueReceivedInOrder
        }
    }
    
    mutating func deliver(to callback: @escaping ((Key, Value) -> Void)) throws {
        try internalQueue.sync {
            for key in buffer.keys.sorted(by: <) {
                guard let value = buffer.removeValue(forKey: key) else {
                    throw BufferError.noValueForKey(key)
                }
                
                DispatchQueue.main.async {
                    callback(key, value)
                }
            }
        }
    }
}
