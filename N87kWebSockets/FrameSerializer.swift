//
//  FrameSerializer.swift
//  N87kWebSockets
//
//  Created by jacob berkman on 9/24/14.
//  Copyright © 2014 jacob berkman
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the “Software”), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.

//  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

import Foundation

class FrameSerializer: NSObject {

    private struct Const {
        static let MaxHeaderLength = 12
    }

    private enum State {
        case Header(masked: Bool)
        case MaskedData(bytesRemaining: UInt64, mask: [UInt8], maskOffset: Int)
    }

    private var state: State

    init(masked: Bool) {
        state = .Header(masked: masked)
        super.init()
    }

    func beginFrameWithOpCode(opCode: OpCode, isFinal: Bool, length: UInt64) -> NSData? {
        switch state {
        case .Header(let masked):
            let data = NSMutableData(capacity: Const.MaxHeaderLength)
            data.length = 2

            var bytes = UnsafeMutablePointer<UInt8>(data.mutableBytes)

            bytes.memory = (isFinal ? HeaderMasks.Fin : 0) | opCode.rawValue
            bytes += 1

            bytes.memory = masked.masked ? HeaderMasks.Mask : 0

            if length > UInt64(UInt16.max) {
                bytes.memory |= ExtendedLength.Long
                data.increaseLengthBy(sizeof(UInt64))
                bytes += 1
                UnsafeMutablePointer<UInt64>(bytes).memory = length.bigEndian
                bytes += sizeof(UInt64)
            } else if length >= UInt64(ExtendedLength.Short) {
                bytes.memory |= ExtendedLength.Short
                data.increaseLengthBy(sizeof(UInt16))
                bytes += 1
                UnsafeMutablePointer<UInt16>(bytes).memory = UInt16(length).bigEndian
                bytes += sizeof(UInt16)
            } else {
                bytes.memory |= UInt8(length)
                bytes += 1
            }
            if masked.masked {
                data.increaseLengthBy(sizeof(UInt32))
                let mask = UnsafeMutableBufferPointer<UInt8>(start: bytes, count: sizeof(UInt32))
                if SecRandomCopyBytes(kSecRandomDefault, UInt(mask.count), mask.baseAddress) != 0 {
                    dlog("Could not generate random mask.")
                    return nil
                }
                state = .MaskedData(bytesRemaining: length, mask: [UInt8](mask), maskOffset: 0)
            } else {
                state = .Header(masked: false)
            }
            return data

        default:
            fatalError("Not ready to write header.")
        }
    }

    func maskedData(data: NSData) -> NSData {
        switch state {
        case .MaskedData(let bytesRemaining, let mask, let maskOffset):
            assert(UInt64(data.length) <= bytesRemaining, "Buffer overflow")
            let buffer = NSMutableData(capacity: data.length)
            buffer.length = data.length

            let src = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(data.bytes), count: data.length)
            let dst = UnsafeMutableBufferPointer<UInt8>(start: UnsafeMutablePointer<UInt8>(buffer.mutableBytes), count: buffer.length)

            let safeMaskOffset = maskOffset - mask.count
            for i in 0 ..< data.length {
                dst[i] = src[i] ^ mask[(mask.count + (safeMaskOffset + i) % mask.count) % mask.count]
            }

            if bytesRemaining == UInt64(data.length) {
                state = .Header(masked: true)
            } else {
                state = .MaskedData(bytesRemaining: bytesRemaining - data.length, mask: mask, maskOffset: (mask.count + (safeMaskOffset + buffer.length) % mask.count) % mask.count)
            }
            return buffer

        default:
            fatalError("Not masking data")
        }
    }
   
}
