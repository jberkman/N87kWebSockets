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

    let request: NSURLRequest
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
        return "\(key!)\(GUIDs.WebSocket)".N87k_SHA1Digest
    }

    init(request: NSURLRequest) {
        self.request = request
        super.init()
//        if request.URL.host == nil ||
//            "GET" != request.HTTPMethod ||
//            scheme == nil {
//                return nil
//        }
    }

    private var scheme: Scheme? {
        return request.URL.scheme != nil ? Scheme.fromRaw(request.URL.scheme!) : nil
    }

    var requestData: NSData? {
        if key == nil {
            return nil
        }

        let port = request.URL.port != nil && request.URL.port != scheme!.defaultPort ? ":\(request.URL.port!)" : ""

        let requestMessage = CFHTTPMessageCreateRequest(kCFAllocatorDefault, request.HTTPMethod! as NSString, request.URL, HTTPVersions.HTTP1_1).takeRetainedValue()
        let headers: [NSString: NSString] = [
            HTTPHeaderFields.Host: "\(request.URL.host!)\(port)",
            HTTPHeaderFields.Connection: HTTPHeaderValues.Upgrade,
            HTTPHeaderFields.Upgrade: HTTPHeaderValues.WebSocket,
            HTTPHeaderFields.SecWebSocketVersion: HTTPHeaderValues.Version,
            HTTPHeaderFields.SecWebSocketKey: key!
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

    func readData(data: NSData) -> Result {
        CFHTTPMessageAppendBytes(responseMessage, UnsafePointer<UInt8>(data.bytes), data.length)
        if CFHTTPMessageIsHeaderComplete(responseMessage) == Boolean(0) {
            return .Incomplete
        }

        var response: NSHTTPURLResponse?
        var responseData: NSData?
        if let HTTPVersion: NSString = CFHTTPMessageCopyVersion(responseMessage)?.takeRetainedValue() {
            let statusCode = CFHTTPMessageGetResponseStatusCode(responseMessage)
            if let headerFields: NSDictionary = CFHTTPMessageCopyAllHeaderFields(responseMessage)?.takeRetainedValue() {
                if HTTPVersion != HTTPVersions.HTTP1_1 || statusCode != HTTPStatusCodes.Upgrade ||
                    headerFields[HTTPHeaderFields.Connection]?.lowercaseString != HTTPHeaderValues.Upgrade.lowercaseString ||
                    headerFields[HTTPHeaderFields.Upgrade]?.lowercaseString != HTTPHeaderValues.WebSocket.lowercaseString ||
                    headerFields[HTTPHeaderFields.SecWebSocketAccept] as? NSString != expectedAccept ||
                    headerFields[HTTPHeaderFields.SecWebSocketExtensions] != nil {
                        NSLog("%@ Invalid HTTP version %@, status code: %@, or header fields: %@", __FUNCTION__, HTTPVersion, "\(statusCode)", headerFields)
                } else {
                    let response = NSHTTPURLResponse(URL: request.URL, statusCode: statusCode, HTTPVersion: HTTPVersion, headerFields: headerFields)
                    let responseData = CFHTTPMessageCopyBody(responseMessage)?.takeRetainedValue() as? AnyObject as? NSData
                    return .Response(response, responseData)
                }
            } else {
                NSLog("%@ No header fields", __FUNCTION__)
            }
        } else {
            NSLog("%@ No HTTP Version", __FUNCTION__)
        }
        return .Invalid
    }
}
