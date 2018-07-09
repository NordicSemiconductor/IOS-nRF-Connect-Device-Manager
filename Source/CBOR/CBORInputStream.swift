/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

public protocol CBORInputStream {
	mutating func popByte() throws -> UInt8
	mutating func popBytes(_ n: Int) throws -> ArraySlice<UInt8>
}

// FYI: https://openradar.appspot.com/23255436
struct ArraySliceUInt8 {
	var slice : ArraySlice<UInt8>
}

struct ArrayUInt8 {
    var array : Array<UInt8>
}

extension ArraySliceUInt8: CBORInputStream {

	mutating func popByte() throws -> UInt8 {
        guard slice.count > 0 else { throw CBORError.unfinishedSequence }
		return slice.removeFirst()
	}

	mutating func popBytes(_ n: Int) throws -> ArraySlice<UInt8> {
        guard slice.count >= n else { throw CBORError.unfinishedSequence }
		let result = slice.prefix(n)
		slice = slice.dropFirst(n)
		return result
	}
}

extension ArrayUInt8: CBORInputStream {
    
    mutating func popByte() throws -> UInt8 {
        guard array.count > 0 else { throw CBORError.unfinishedSequence }
        return array.removeFirst()
    }
    
    mutating func popBytes(_ n: Int) throws -> ArraySlice<UInt8> {
        guard array.count >= n else { throw CBORError.unfinishedSequence }
        let res = array.prefix(n)
        array = Array(array.dropFirst(n))
        return res
    }
}
