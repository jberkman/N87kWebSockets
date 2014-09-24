//
//  WebSocketClientHandshake.swift
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

class WebSocketClientHandshake: NSObject {
    enum Handshake {
        case Incomplete
        case Invalid
        case Response(NSHTTPURLResponse, NSData?)
    }

    private let request: NSURLRequest
    private let responseMessage = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, Boolean(0)).takeRetainedValue()
    private lazy var key: String? = {
        let keyLength = 16
        let data = NSMutableData(length: keyLength)
        if SecRandomCopyBytes(kSecRandomDefault, UInt(keyLength), UnsafeMutablePointer<UInt8>(data.mutableBytes)) != 0 {
            NSLog("Could not generate random key");
            return nil
        }
        return data.base64EncodedStringWithOptions(nil)
    }()
    private var expectedAccept: String {
        return "\(key!)\(Const.GUID)".N87k_SHA1Digest
    }

    private struct Const {
        static let HTTPVersion: NSString = "HTTP/1.1"
        static let GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        static let UpgradeStatusCode = 101
    }

    private struct HeaderKeys {
        static let Connection = "Connection"
        static let Host = "Host"
        static let SecWebSocketAccept = "Sec-WebSocket-Accept"
        static let SecWebSocketKey = "Sec-WebSocket-Key"
        static let SecWebSocketVersion = "Sec-WebSocket-Version"
        static let SecWebSocketExtensions = "Sec-WebSocket-Extensions"
        static let Upgrade = "Upgrade"
    }

    private struct HeaderValues {
        static let Upgrade = "upgrade"
        static let Version = "13"
        static let WebSocket = "websocket"
    }

    init(request: NSURLRequest) {
        self.request = request
        super.init()
    }

    private var scheme: Scheme? {
        return request.URL.scheme != nil ? Scheme.fromRaw(request.URL.scheme!) : nil
    }

    var requestData: NSData? {
        if key == nil {
            return nil
        }

        let port = request.URL.port != nil && request.URL.port != scheme!.defaultPort ? ":\(request.URL.port!)" : ""

        let requestMessage = CFHTTPMessageCreateRequest(kCFAllocatorDefault, request.HTTPMethod! as NSString, request.URL, Const.HTTPVersion).takeRetainedValue()
        let headers: [NSString: NSString] = [
            HeaderKeys.Host: "\(request.URL.host!)\(port)",
            HeaderKeys.Connection: HeaderValues.Upgrade,
            HeaderKeys.Upgrade: HeaderValues.WebSocket,
            HeaderKeys.SecWebSocketVersion: HeaderValues.Version,
            HeaderKeys.SecWebSocketKey: key!
        ]
        if let requestHeaders = request.allHTTPHeaderFields as? [NSString: NSString] {
            for (k, v) in requestHeaders {
                if headers[k] == nil {
                    CFHTTPMessageSetHeaderFieldValue(requestMessage, k, v)
                }
            }

        }
        for (k, v) in headers {
            CFHTTPMessageSetHeaderFieldValue(requestMessage, k, v)
        }

        return CFHTTPMessageCopySerializedMessage(requestMessage)?.takeRetainedValue()
    }

    func parseData(data: NSData) -> Handshake {
        CFHTTPMessageAppendBytes(responseMessage, UnsafePointer<UInt8>(data.bytes), data.length)
        if CFHTTPMessageIsHeaderComplete(responseMessage) == Boolean(0) {
            return .Incomplete
        }

        var response: NSHTTPURLResponse?
        var responseData: NSData?
        if let HTTPVersion: NSString = CFHTTPMessageCopyVersion(responseMessage)?.takeRetainedValue() {
            let statusCode = CFHTTPMessageGetResponseStatusCode(responseMessage)
            if let headerFields: NSDictionary = CFHTTPMessageCopyAllHeaderFields(responseMessage)?.takeRetainedValue() {
                if HTTPVersion == Const.HTTPVersion && statusCode == Const.UpgradeStatusCode &&
                    headerFields[HeaderKeys.Connection]?.lowercaseString == HeaderValues.Upgrade &&
                    headerFields[HeaderKeys.Upgrade]?.lowercaseString == HeaderValues.WebSocket &&
                    headerFields[HeaderKeys.SecWebSocketAccept] as? NSString == expectedAccept &&
                    headerFields[HeaderKeys.SecWebSocketExtensions] == nil {
                        let response = NSHTTPURLResponse(URL: request.URL, statusCode: statusCode, HTTPVersion: HTTPVersion, headerFields: headerFields)
                        let responseData = CFHTTPMessageCopyBody(responseMessage)?.takeRetainedValue()
                        return .Response(response, responseData)
                }
            }
        }
        return .Invalid
    }
}
