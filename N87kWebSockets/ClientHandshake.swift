//
//  ClientHandshake.swift
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

import CFNetwork
import Foundation
import Security

class ClientHandshake: NSObject {
    enum Result {
        case Incomplete
        case Invalid
        case Response(NSHTTPURLResponse, NSData?)
    }
    private enum WhitespaceState {
        case None
        case NewLine1
        case CarriageReturn1
        case NewLine2
        case CarriageReturn2
        func stateWithByte(byte: Byte) -> WhitespaceState {
            switch (self, byte) {
            case (.NewLine2, 0xa): return .CarriageReturn2
            case (.CarriageReturn1, 0xd): return .NewLine2
            case (.NewLine1, 0xa): return .CarriageReturn1
            case (_, 0xd): return .NewLine1
            default: return .None
            }
        }
    }
    private var whitespaceState = WhitespaceState.None

    let request: NSURLRequest
    private let responseMessage = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, Boolean(0)).takeRetainedValue()
    private lazy var key: String? = {
        let keyLength = 16
        if let data = NSMutableData(length: keyLength) {
            if SecRandomCopyBytes(kSecRandomDefault, UInt(keyLength), UnsafeMutablePointer<UInt8>(data.mutableBytes)) == 0 {
                return data.base64EncodedStringWithOptions(nil)
            } else {
                dlog("\(__FUNCTION__): Could not generate random key")
            }
        } else {
            dlog("\(__FUNCTION__): Could not allocate buffer")
        }
        return nil
    }()
    private var expectedAccept: String {
        return "\(key!)\(GUIDs.WebSocket)".N87k_SHA1Digest
    }

    init?(request: NSURLRequest) {
        let tmpRequest = NSMutableURLRequest(URL: request.URL)
        self.request = tmpRequest
        super.init()
        if request.URL.host == nil || "GET" != request.HTTPMethod || scheme == nil || key == nil {
            return nil
        }
        if let port = request.URL.port {
            tmpRequest.setValue("\(request.URL.host!):\(port)", forHTTPHeaderField: HTTPHeaderFields.Host)
        } else {
            tmpRequest.setValue(request.URL.host, forHTTPHeaderField: HTTPHeaderFields.Host)
        }
        tmpRequest.setValue(HTTPHeaderValues.Upgrade, forHTTPHeaderField: HTTPHeaderFields.Connection)
        tmpRequest.setValue(HTTPHeaderValues.WebSocket, forHTTPHeaderField: HTTPHeaderFields.Upgrade)
        tmpRequest.setValue(HTTPHeaderValues.Version, forHTTPHeaderField: HTTPHeaderFields.SecWebSocketVersion)
        tmpRequest.setValue(key, forHTTPHeaderField: HTTPHeaderFields.SecWebSocketKey)
    }

    private var scheme: Scheme? {
        if let scheme = request.URL.scheme {
            return Scheme(rawValue: scheme)
        }
        return nil
    }

    func readData(data: NSData) -> Result {
        var responseData: NSData?
        let end = data.bytes + data.length
        for var byte = data.bytes; byte < end; byte++ {
            whitespaceState = whitespaceState.stateWithByte(UnsafePointer<Byte>(byte).memory)
            if whitespaceState == .CarriageReturn2 {
                responseData = NSData(bytes: byte + 1, length: end - byte - 1)
                break

            }
        }
        CFHTTPMessageAppendBytes(responseMessage, UnsafePointer<UInt8>(data.bytes), data.length)
        if CFHTTPMessageIsHeaderComplete(responseMessage) == Boolean(0) {
            return .Incomplete
        }

        if let response = NSHTTPURLResponse(N87k_URL: request.URL, HTTPMessage: responseMessage) {
            if response.statusCode == HTTPStatusCodes.Upgrade {
                let headerFields = response.allHeaderFields
                if  headerFields[HTTPHeaderFields.Connection]?.lowercaseString != HTTPHeaderValues.Upgrade.lowercaseString ||
                    headerFields[HTTPHeaderFields.Upgrade]?.lowercaseString != HTTPHeaderValues.WebSocket.lowercaseString ||
                    headerFields[HTTPHeaderFields.SecWebSocketAccept] as? NSString != expectedAccept ||
                    headerFields[HTTPHeaderFields.SecWebSocketExtensions] != nil {
                        dlog("\(__FUNCTION__) Invalid status code: \(response.statusCode) or header fields: \(headerFields)")
                } else {
                    return .Response(response, responseData)
                }
            } else {
                dlog("\(__FUNCTION__): Invalid status code: \(response.statusCode)")
            }
        } else {
            dlog("\(__FUNCTION__): Invalid response")
        }
        return .Invalid
    }
}
