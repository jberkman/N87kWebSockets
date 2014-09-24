//
//  FrameInputStream.swift
//  N87kWebSockets
//
//  Created by jacob berkman on 9/22/14.
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

//    0                   1                   2                   3
//    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//    +-+-+-+-+-------+-+-------------+-------------------------------+
//    |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
//    |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
//    |N|V|V|V|       |S|             |   (if payload len==126/127)   |
//    | |1|2|3|       |K|             |                               |
//    +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
//    |     Extended payload length continued, if payload len == 127  |
//    + - - - - - - - - - - - - - - - +-------------------------------+
//    |                               |Masking-key, if MASK set to 1  |
//    +-------------------------------+-------------------------------+
//    | Masking-key (continued)       |          Payload Data         |
//    +-------------------------------- - - - - - - - - - - - - - - - +
//    :                     Payload Data continued ...                :
//    + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
//    |                     Payload Data continued ...                |
//    +---------------------------------------------------------------+

enum OpCode: UInt8 {
    case Continuation = 0x0
    case Text = 0x1
    case Binary = 0x2
    case ConnectionClose = 0x8
    case Ping = 0x9
    case Pong = 0xA
}

protocol FrameInputStreamDelegate: NSObjectProtocol {
    func frameInputStream(frameInputStream: FrameInputStream, didBeginFrameWithOpCode opCode: OpCode, isFinal: Bool, reservedBits: (Bit, Bit, Bit))
    func frameInputStream(frameInputStream: FrameInputStream, didReadData data: NSData)
    func frameInputStreamDidEndFrame(frameInputStream: FrameInputStream)
}

class FrameInputStream: NSObject {

    private struct Const {
        static let ExtendedPayload16 = UInt8(126)
        static let ExtendedPayload64 = UInt8(127)
    }

    private enum ParseState {
        case OpCode, Length
        case ExtendedLength(length: UInt64, shiftOffset: UInt64)
        case UnmaskedData(bytesRemaining: UInt64)
        case MaskingKey(bytesRemaining: UInt64, mask: [UInt8])
        case MaskedData(bytesRemaining: UInt64, mask: [UInt8], maskOffset: Int, buffer: NSMutableData?)
        case Error
    }

    private struct Masks {
        static let Fin = UInt8(0x80)
        static let Rsv1 = UInt8(0x40)
        static let Rsv2 = UInt8(0x20)
        static let Rsv3 = UInt8(0x10)
        static let OpCode = UInt8(0x7)

        static let Mask = UInt8(0x80)
        static let PayloadLen = UInt8(0x7f)
    }

    private var state = ParseState.OpCode

    private let masked: Bool
    init(masked: Bool) {
        assert(!masked, "Masked streams are not supported.")
        self.masked = masked
        super.init()
    }

    var delegate: FrameInputStreamDelegate?

    func readData(data: NSData) -> NSError? {
        if data.length == 0 {
            return nil
        }
        let start = UnsafePointer<UInt8>(data.bytes)
        let finish = start + data.length

        for var p = start; p < finish; p += 1 {
            let byte = p.memory
            switch state {
            case .OpCode:
                if let opCode = OpCode.fromRaw(byte & Masks.OpCode) {
                    if byte & (Masks.Rsv1 | Masks.Rsv2 | Masks.Rsv3) != 0 {
                        state = .Error
                        return NSError(domain: ErrorDomain, code: Errors.InvalidReservedBit.toRaw(), userInfo: nil)
                    }
                    delegate?.frameInputStream(self, didBeginFrameWithOpCode: opCode, isFinal: byte & Masks.Fin == Masks.Fin, reservedBits: (.Zero, .Zero, .Zero))
                } else {
                    state = .Error
                    return NSError(domain: ErrorDomain, code: Errors.InvalidOpCode.toRaw(), userInfo: nil)
                }
                state = .Length

            case .Length:
                if (byte & Masks.Mask == Masks.Mask) != masked {
                    state = .Error
                    return NSError(domain: ErrorDomain, code: Errors.InvalidMask.toRaw(), userInfo: nil)
                }
                switch (byte & Masks.PayloadLen, masked) {
                case (Const.ExtendedPayload16, _):
                    state = .ExtendedLength(length: 0, shiftOffset: 8)
                case (Const.ExtendedPayload64, _):
                    state = .ExtendedLength(length: 0, shiftOffset: 56)
                case (let payloadLen, true):
                    state = .MaskingKey(bytesRemaining: UInt64(payloadLen), mask: [UInt8]())
                case (let payloadLen, false):
                    state = .UnmaskedData(bytesRemaining: UInt64(payloadLen))
                default:
                    fatalError("Should not be reached.")
                }

            case .ExtendedLength(let length, shiftOffset: 0):
                let bytesRemaining = length + UInt64(byte)
                if masked {
                    state = .MaskingKey(bytesRemaining: bytesRemaining, mask: [UInt8]())
                } else {
                    state = .UnmaskedData(bytesRemaining: bytesRemaining)
                }

            case .ExtendedLength(let length, let shiftOffset):
                state = .ExtendedLength(length: length + UInt64(byte) << shiftOffset, shiftOffset: shiftOffset >> 4)

            case .UnmaskedData(let bytesRemaining):
                let bytesRead64 = min(bytesRemaining, UInt64(p.distanceTo(finish)))
                let bytesRead = Int(bytesRead64)
                delegate?.frameInputStream(self, didReadData: NSData(bytes: UnsafePointer<Void>(p), length: bytesRead))
                p += bytesRead - 1 // take into account loop increment
                if bytesRemaining == bytesRead64 {
                    delegate?.frameInputStreamDidEndFrame(self)
                    state = .OpCode
                } else {
                    state = .UnmaskedData(bytesRemaining: bytesRemaining - bytesRead64)
                }

/*
            case .MaskingKey(let bytesRemaining, let mask):
                let newMask = mask + [byte]
                if mask.count < 4 {
                    state = .MaskingKey(bytesRemaining: bytesRemaining, mask: newMask)
                } else {
                    state = .MaskedData(bytesRemaining, newMask, 0, nil)
                }

            case .MaskedData(let bytesRemaining, let mask, let maskOffset, .None):
                let bytesRead64 = min(bytesRemaining, UInt64(p.distanceTo(finish)))
                let bytesRead = Int(bytesRead64)
                let buffer = NSMutableData(capacity: bytesRead)
                buffer.length = 1
                UnsafeMutablePointer<UInt8>(buffer.mutableBytes).memory = byte ^ mask[maskOffset]
                state = .MaskedData(bytesRemaining - UInt64(1), mask, Int((maskOffset + 1) % mask.count), buffer)

            case .MaskedData(let bytesRemaining, let mask, let maskOffset, let .Some(buffer)):
                buffer.increaseLengthBy(1)
                UnsafeMutablePointer<UInt8>(buffer.mutableBytes)[buffer.length - 1] = byte ^ mask[maskOffset]
                state = .MaskedData(bytesRemaining - UInt64(1), mask, (maskOffset + 1) % mask.count, buffer)
*/
            default:
                fatalError("Unexpected state while parsing.")
            }
        }
/*
        switch state {
        case .MaskedData(let bytesRemaining, let mask, let maskOffset, .Some(data)):
            delegate?.frameInputStream(self, didReadData: data)
            if bytesRemaining == 0 {
                delegate?.frameInputStreamDidEndFrame(self)
                state = .OpCode
            } else {
                state = .MaskedData(bytesRemaining, mask, maskOffset, nil)
            }
        }
*/
        return nil
    }

}
