/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

extension CBOR: CustomStringConvertible {
    
    private func wrapQuotes(_ string: String) -> String {
        return "\"\(string)\""
    }
    
    public var description: String {
        switch self {
        case let .unsignedInt(l): return l.description
        case let .negativeInt(l): return l.description
        case let .byteString(l):  return wrapQuotes(Data(l).base64EncodedString())
        case let .utf8String(l):  return wrapQuotes(l)
        case let .array(l):       return l.description
        case let .map(l):         return l.description.replaceFirst(of: "[", with: "{").replaceLast(of: "]", with: "}")
        case let .tagged(_, l):   return l.description // TODO what to do with tags
        case let .simple(l):      return l.description
        case let .boolean(l):     return l.description
        case .null:               return "null"
        case .undefined:          return "null"
        case let .half(l):        return l.description
        case let .float(l):       return l.description
        case let .double(l):      return l.description
        case .break:              return ""
        }
    }
    
    public static func toObjectMap<V: CBORMappable>(map: [CBOR:CBOR]?) throws -> [String:V]? {
        guard let map = map else {
            return nil
        }
        var objMap = [String:V]()
        for (key, value) in map {
            if case let CBOR.utf8String(keyString) = key {
                let v = try V(cbor: value)
                objMap.updateValue(v, forKey: keyString)
            }
        }
        return objMap
    }
    
    public static func toObjectArray<V: CBORMappable>(array: [CBOR]?) throws -> [V]? {
        guard let array = array else {
            return nil
        }
        var objArray = [V]()
        for cbor in array {
            let obj = try V(cbor: cbor)
            objArray.append(obj)
        }
        return objArray
    }
}

//***********************************************************************************************
// MARK: CBORMappable
//***********************************************************************************************

public class CBORMappable {
    required public init(cbor: CBOR?) throws {
    }
}

//class JSONEncoder {
//    private var istream : CBORInputStream
//
//    public init(stream: CBORInputStream) {
//        istream = stream
//    }
//
//    public init(input: ArraySlice<UInt8>) {
//        istream = ArraySliceUInt8(slice: input)
//    }
//
//    public init(input: [UInt8]) {
//        istream = ArrayUInt8(array: input)
//    }
//
//    private func readUInt<T: UnsignedInteger>(_ n: Int) throws -> T {
//        return UnsafeRawPointer(Array(try istream.popBytes(n).reversed())).load(as: T.self)
//    }
//
//    private func readN(_ n: Int) throws -> [String] {
//        return try (0..<n).map { _ in return try decodeItem() }
//    }
//
//    private func readUntilBreak() throws -> [String] {
//        var result : [CBOR] = []
//        var cur = try decodeItem()
//        while (cur != CBOR.break) {
//            guard let curr = cur else { throw CBORError.unfinishedSequence }
//            result.append(curr)
//            cur = try decodeItem()
//        }
//        return result
//    }
//
//    private func readNPairs(_ n: Int) throws -> [CBOR : CBOR] {
//        var result : [CBOR : CBOR] = [:]
//        for _ in (0..<n) {
//            guard let key  = try decodeItem() else { throw CBORError.unfinishedSequence }
//            guard let val  = try decodeItem() else { throw CBORError.unfinishedSequence }
//            result[key] = val
//        }
//        return result
//    }
//
//    private func readPairsUntilBreak() throws -> [CBOR : CBOR] {
//        var result : [CBOR : CBOR] = [:]
//        var key = try decodeItem()
//        var val = try decodeItem()
//        while (key != CBOR.break) {
//            guard let okey = key else { throw CBORError.unfinishedSequence }
//            guard let oval = val else { throw CBORError.unfinishedSequence }
//            result[okey] = oval
//            do { key = try decodeItem() } catch CBORError.unfinishedSequence { key = nil }
//            guard (key != CBOR.break) else { break } // don't eat the val after the break!
//            do { val = try decodeItem() } catch CBORError.unfinishedSequence { val = nil }
//        }
//        return result
//    }
//
//    public func decodeItem() throws -> String {
//        switch try istream.popByte() {
//        case let b where b <= 0x17: return String(UInt(b))
//        case 0x18: return String(UInt(try istream.popByte()))
//        case 0x19: return String(UInt(try readUInt(2) as UInt16))
//        case 0x1a: return String(UInt(try readUInt(4) as UInt32))
//        case 0x1b: return String(UInt(try readUInt(8) as UInt64))
//
//        case let b where 0x20 <= b && b <= 0x37: return String(UInt(b - 0x20))
//        case 0x38: return String(UInt(try istream.popByte()))
//        case 0x39: return String(UInt(try readUInt(2) as UInt16))
//        case 0x3a: return String(UInt(try readUInt(4) as UInt32))
//        case 0x3b: return String(UInt(try readUInt(8) as UInt64))
//
//        case let b where 0x40 <= b && b <= 0x57: return Data(Array(try istream.popBytes(Int(b - 0x40)))).base64EncodedString()
//        case 0x58:
//            let numBytes: Int = Int(try istream.popByte())
//            return Data(Array(try istream.popBytes(numBytes))).base64EncodedString()
//        case 0x59: return Data(Array(try istream.popBytes(Int(try readUInt(2) as UInt16)))).base64EncodedString()
//        case 0x5a: return Data(Array(try istream.popBytes(Int(try readUInt(4) as UInt32)))).base64EncodedString()
//        case 0x5b: return Data(Array(try istream.popBytes(Int(try readUInt(8) as UInt64)))).base64EncodedString()
//        case 0x5f: return Data(try readUntilBreak().flatMap { x -> [UInt8] in guard case .byteString(let r) = x else { throw CBORError.wrongTypeInsideSequence }; return r }).base64EncodedString()
//
//        case let b where 0x60 <= b && b <= 0x77: return String(try Util.decodeUtf8(try istream.popBytes(Int(b - 0x60))))
//        case 0x78:
//            let numBytes: Int = Int(try istream.popByte())
//            return String(try Util.decodeUtf8(try istream.popBytes(numBytes)))
//        case 0x79: return String(try Util.decodeUtf8(try istream.popBytes(Int(try readUInt(2) as UInt16))))
//        case 0x7a: return String(try Util.decodeUtf8(try istream.popBytes(Int(try readUInt(4) as UInt32))))
//        case 0x7b: return String(try Util.decodeUtf8(try istream.popBytes(Int(try readUInt(8) as UInt64))))
//        case 0x7f: return String(try readUntilBreak().map { x -> String in guard case .utf8String(let r) = x else { throw CBORError.wrongTypeInsideSequence }; return r }.joined(separator: ""))
//
//        case let b where 0x80 <= b && b <= 0x97: return try readN(Int(b - 0x80)).description
//        case 0x98: return try readN(Int(try istream.popByte())).description
//        case 0x99: return try readN(Int(try readUInt(2) as UInt16)).description
//        case 0x9a: return try readN(Int(try readUInt(4) as UInt32)).description
//        case 0x9b: return try readN(Int(try readUInt(8) as UInt64)).description
//        case 0x9f: return try readUntilBreak().description
//
//        case let b where 0xa0 <= b && b <= 0xb7: return CBOR.map(try readNPairs(Int(b - 0xa0)))
//        case 0xb8: return CBOR.map(try readNPairs(Int(try istream.popByte())))
//        case 0xb9: return CBOR.map(try readNPairs(Int(try readUInt(2) as UInt16)))
//        case 0xba: return CBOR.map(try readNPairs(Int(try readUInt(4) as UInt32)))
//        case 0xbb: return CBOR.map(try readNPairs(Int(try readUInt(8) as UInt64)))
//        case 0xbf: return CBOR.map(try readPairsUntilBreak())
//
//        case let b where 0xc0 <= b && b <= 0xd7:
//            guard let item = try decodeItem() else { throw CBORError.unfinishedSequence }
//            return CBOR.tagged(UInt8(b - 0xc0), item)
//        case 0xd8:
//            let tag = UInt8(try istream.popByte())
//            guard let item = try decodeItem() else { throw CBORError.unfinishedSequence }
//            return CBOR.tagged(tag, item)
//        case 0xd9:
//            let tag = UInt8(try readUInt(2) as UInt16)
//            guard let item = try decodeItem() else { throw CBORError.unfinishedSequence }
//            return CBOR.tagged(tag, item)
//        case 0xda:
//            let tag = UInt8(try readUInt(4) as UInt32)
//            guard let item = try decodeItem() else { throw CBORError.unfinishedSequence }
//            return CBOR.tagged(tag, item)
//        case 0xdb:
//            let tag = UInt8(try readUInt(8) as UInt64)
//            guard let item = try decodeItem() else { throw CBORError.unfinishedSequence }
//            return CBOR.tagged(tag, item)
//
//        case let b where 0xe0 <= b && b <= 0xf3: return CBOR.simple(b - 0xe0)
//        case 0xf4: return CBOR.boolean(false)
//        case 0xf5: return CBOR.boolean(true)
//        case 0xf6: return CBOR.null
//        case 0xf7: return CBOR.undefined
//        case 0xf8: return CBOR.simple(try istream.popByte())
//
//        case 0xf9:
//            let ptr = UnsafeRawPointer(Array(try istream.popBytes(2).reversed())).bindMemory(to: UInt16.self, capacity: 1)
//            return CBOR.half(loadFromF16(ptr))
//        case 0xfa:
//            return CBOR.float(UnsafeRawPointer(Array(try istream.popBytes(4).reversed())).load(as: Float32.self))
//        case 0xfb:
//            return CBOR.double(UnsafeRawPointer(Array(try istream.popBytes(8).reversed())).load(as: Float64.self))
//
//        case 0xff: return CBOR.break
//        default: return nil
//        }
//    }
//}
