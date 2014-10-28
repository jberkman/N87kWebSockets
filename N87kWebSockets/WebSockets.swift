//
//  WebSockets.swift
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
    var isControl: Bool {
        return rawValue & 0xF0 != 0
    }
}

struct HeaderMasks {
    static let Fin = UInt8(0x80)
    static let Rsv1 = UInt8(0x40)
    static let Rsv2 = UInt8(0x20)
    static let Rsv3 = UInt8(0x10)
    static let OpCode = UInt8(0x7)

    static let Mask = UInt8(0x80)
    static let PayloadLen = UInt8(0x7f)
}

struct ExtendedLength {
    static let Short = UInt8(126)
    static let Long = UInt8(127)
}

public let ErrorDomain = "N87kWebSocketErrorDomain"

public enum Errors: Int {
    case InvalidOpCode = 1, InvalidReservedBit, InvalidLength, InvalidMask, InvalidHandshake
}

struct HTTPVersions {
    static let HTTP1_1: NSString = "HTTP/1.1"
}

struct GUIDs {
    static let WebSocket = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
}

struct HTTPStatusCodes {
    static let Upgrade = 101
}

struct HTTPHeaderFields {
    static let Connection = "Connection"
    static let Host = "Host"
    static let SecWebSocketAccept = "Sec-WebSocket-Accept"
    static let SecWebSocketKey = "Sec-WebSocket-Key"
    static let SecWebSocketVersion = "Sec-WebSocket-Version"
    static let SecWebSocketExtensions = "Sec-WebSocket-Extensions"
    static let Upgrade = "Upgrade"
}

struct HTTPHeaderValues {
    static let Upgrade = "Upgrade"
    static let Version = "13"
    static let WebSocket = "websocket"
}

public enum Scheme: String {
    case WS = "ws"
    case WSS = "wss"
    
    public var isSecure: Bool { return self == WSS }
    public var defaultPort: Int { return self == WS ? 80 : 443 }
}

public let NormalStatusCode: UInt16 = 1000
public let GoingAwayStatusCode: UInt16 = 1001
public let ProtocolErrorStatusCode: UInt16 = 1002
public let UnacceptableDataStatusCode: UInt16 = 1003
public let PolicyViolationStatusCode: UInt16 = 1008
public let MessageTooLargeStatusCode: UInt16 = 1009
public let MissingExtensionStatusCode: UInt16 = 1010
public let UnexpectedConditionStatusCode: UInt16 = 1011
