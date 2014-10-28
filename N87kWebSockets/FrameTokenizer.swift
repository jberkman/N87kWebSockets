//
//  FrameTokenizer.swift
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

protocol FrameTokenizerDelegate: NSObjectProtocol {
    func frameTokenizer(frameTokenizer: FrameTokenizer, didBeginFrameWithOpCode opCode: OpCode, isFinal: Bool, reservedBits: (Bit, Bit, Bit))
    func frameTokenizer(FrameTokenizer: FrameTokenizer, didReadFrameLength frameLength: UInt64)
    func frameTokenizer(frameTokenizer: FrameTokenizer, didReadData data: NSData)
    func frameTokenizerDidEndFrame(frameTokenizer: FrameTokenizer)
}

class FrameTokenizer: NSObject {

    private enum State {
        case OpCode, Length(isControl: Bool)
        case ExtendedLength(length: UInt64, shiftOffset: Int)
        case UnmaskedData(bytesRemaining: UInt64)
        case MaskingKey(bytesRemaining: UInt64, mask: [UInt8])
        case MaskedData(bytesRemaining: UInt64, mask: GeneratorOf<UInt8>, buffer: NSMutableData?)
        case Error
    }

    private var state: State = State.OpCode {
        didSet {
            switch state {
            case .OpCode:
                delegate?.frameTokenizerDidEndFrame(self)

            case .UnmaskedData(let bytesRemaining):
                switch oldValue {
                case .Length, .ExtendedLength:
                    delegate?.frameTokenizer(self, didReadFrameLength: bytesRemaining)
                default:
                    break
                }
                
            case .MaskingKey(let bytesRemaining, _):
                switch oldValue {
                case .Length, .ExtendedLength:
                    delegate?.frameTokenizer(self, didReadFrameLength: bytesRemaining)
                default:
                    break
                }
                
            default:
                break
            }
        }
    }

    private let masked: Bool
    init(masked: Bool) {
        self.masked = masked
        super.init()
    }

    var delegate: FrameTokenizerDelegate?
    
    private func appendMaskedByte(byte: UInt8) {
        switch state {
        case .MaskedData(let bytesRemaining, var mask, let .Some(buffer)):
            buffer.increaseLengthBy(1)
            UnsafeMutablePointer<UInt8>(buffer.mutableBytes)[buffer.length - 1] = byte ^ mask.next()!
            if bytesRemaining > 1 {
                state = .MaskedData(bytesRemaining: bytesRemaining - UInt64(1), mask: mask, buffer: buffer)
            } else {
                delegate?.frameTokenizer(self, didReadData: buffer)
                state = .OpCode
            }

        default:
            dlog("Invalid state")
        }
    }

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
                if let opCode = OpCode(rawValue: byte & HeaderMasks.OpCode) {
                    if byte & (HeaderMasks.Rsv1 | HeaderMasks.Rsv2 | HeaderMasks.Rsv3) != 0 {
                        state = .Error
                        return NSError(domain: ErrorDomain, code: Errors.InvalidReservedBit.rawValue, userInfo: nil)
                    }
//                    dlog("OpCode: %@", "\(byte)")
                    delegate?.frameTokenizer(self, didBeginFrameWithOpCode: opCode, isFinal: byte & HeaderMasks.Fin == HeaderMasks.Fin, reservedBits: (.Zero, .Zero, .Zero))
                    state = .Length(isControl: opCode.isControl)
                } else {
                    state = .Error
                    return NSError(domain: ErrorDomain, code: Errors.InvalidOpCode.rawValue, userInfo: nil)
                }

            case .Length(let isControl):
                if (byte & HeaderMasks.Mask == HeaderMasks.Mask) != masked {
                    state = .Error
                    return NSError(domain: ErrorDomain, code: Errors.InvalidMask.rawValue, userInfo: nil)
                }
//                dlog("Length: %@", "\(byte)")
                switch (byte & HeaderMasks.PayloadLen, masked) {
                case (ExtendedLength.Short, _) where !isControl.isControl:
                    state = .ExtendedLength(length: 0, shiftOffset: sizeof(UInt16) - sizeof(UInt8))
                case (ExtendedLength.Long, _) where !isControl.isControl:
                    state = .ExtendedLength(length: 0, shiftOffset: sizeof(UInt64) - sizeof(UInt8))
                case (let payloadLen, true):
//                    dlog("got length: %@", "\(payloadLen)")
                    state = .MaskingKey(bytesRemaining: UInt64(payloadLen), mask: [UInt8]())
                case (let payloadLen, false):
//                    dlog("got length: %@", "\(payloadLen)")
                    state = .UnmaskedData(bytesRemaining: UInt64(payloadLen))
                default:
                    state = .Error
                    return NSError(domain: ErrorDomain, code: Errors.InvalidLength.rawValue, userInfo: nil)
                }

            case .ExtendedLength(let length, shiftOffset: 0):
                let bytesRemaining = (length << 8) + UInt64(byte)
                if masked {
                    state = .MaskingKey(bytesRemaining: bytesRemaining, mask: [UInt8]())
                } else {
                    state = .UnmaskedData(bytesRemaining: bytesRemaining)
                }

            case .ExtendedLength(let length, let shiftOffset):
                state = .ExtendedLength(length: UInt64(byte) + (length << 8), shiftOffset: shiftOffset - sizeof(UInt8))

            case .UnmaskedData(let bytesRemaining):
                let bytesRead64 = min(bytesRemaining, UInt64(p.distanceTo(finish)))
                let bytesRead = Int(bytesRead64)
                delegate?.frameTokenizer(self, didReadData: NSData(bytes: UnsafePointer<Void>(p), length: bytesRead))
                p += bytesRead - 1 // take into account loop increment
                if bytesRemaining == bytesRead64 {
                    state = .OpCode
                } else {
                    state = .UnmaskedData(bytesRemaining: bytesRemaining - bytesRead64)
                }

            case .MaskingKey(let bytesRemaining, var mask):
                mask += [byte]
                if mask.count < 4 {
                    state = .MaskingKey(bytesRemaining: bytesRemaining, mask: mask)
                } else {
//                    dlog("got masking key: %@", "\(mask)")
                    state = .MaskedData(bytesRemaining: bytesRemaining, mask: GeneratorOf(RingGenerator(collection: mask)), buffer: nil)
                }

            case .MaskedData(let bytesRemaining, var mask, .None):
                let bytesRead64 = min(bytesRemaining, UInt64(p.distanceTo(finish)))
                let bytesRead = Int(bytesRead64)
                let buffer = NSMutableData(capacity: bytesRead)
                state = .MaskedData(bytesRemaining: bytesRemaining, mask: mask, buffer: NSMutableData(capacity: bytesRead))
                appendMaskedByte(byte)

            case .MaskedData:
                appendMaskedByte(byte)

            default:
                fatalError("Unexpected state while parsing.")
            }
        }
        
        switch state {
        case .MaskedData(let bytesRemaining, var mask, .Some(let buffer)):
//            dlog("bytes remaining: %@", "\(bytesRemaining)")
            delegate?.frameTokenizer(self, didReadData: buffer)
            state = .MaskedData(bytesRemaining: bytesRemaining, mask: mask, buffer: nil)
        default:
            break
        }

        return nil
    }

}
