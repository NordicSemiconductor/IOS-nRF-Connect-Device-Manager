//
//  Pipeline.swift
//  McuManager
//
//  Created by Dinesh Harjani on 27/4/22.
//

import Foundation
import Dispatch

// MARK: - Pipeline

struct Pipeline {
    
    let depth: Int
    
    private let pipelineSemaphore: DispatchSemaphore
    private var pipelineQueue: DispatchQueue
    
    init(depth: Int) {
        let correctedDepth = max(abs(depth), 1)
        self.depth = correctedDepth
        self.pipelineSemaphore = DispatchSemaphore(value: correctedDepth)
        self.pipelineQueue = DispatchQueue(label: String(describing: Self.Type.self), attributes: .concurrent)
    }
    
    func submit(_ item: PipelineItem) {
        pipelineQueue.async {
            pipelineSemaphore.wait()
            item.perform()
            pipelineSemaphore.signal()
        }
    }
}

// MARK: - PipelineItem

struct PipelineItem {
    
    private let closure: () -> Void
    
    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }
    
    func perform() {
        closure()
    }
}
