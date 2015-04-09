//
//  ServerHandshake.swift
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

class ServerHandshake: NSObject {
    enum Result {
        case Incomplete
        case Invalid
        case Request(NSURLRequest)
    }
    
    private let requestMessage = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, Boolean(1)).takeRetainedValue()
    private var key: String?
    private var expectedAccept: String {
        return "\(key!)\(GUIDs.WebSocket)".N87k_SHA1Digest
    }
    private var URL: NSURL?

    var upgradeResponse: NSHTTPURLResponse? {
        return NSHTTPURLResponse(URL: URL!, statusCode: HTTPStatusCodes.Upgrade, HTTPVersion: kCFHTTPVersion1_1 as String, headerFields: [
            HTTPHeaderFields.Connection: HTTPHeaderValues.Upgrade,
            HTTPHeaderFields.Upgrade: HTTPHeaderValues.WebSocket,
            HTTPHeaderFields.SecWebSocketAccept: expectedAccept
        ])
    }
    
    func readData(data: NSData) -> Result {
        CFHTTPMessageAppendBytes(requestMessage, UnsafePointer<UInt8>(data.bytes), data.length)
        if CFHTTPMessageIsHeaderComplete(requestMessage) == Boolean(0) {
            return .Incomplete
        }

        if let request = NSMutableURLRequest(N87k_HTTPMessage: requestMessage) {
            URL = request.URL
            if !request.N87k_webSocketRequest {
                return .Request(request)
            }
            let version = request.valueForHTTPHeaderField(HTTPHeaderFields.SecWebSocketVersion)
            key = request.valueForHTTPHeaderField(HTTPHeaderFields.SecWebSocketKey)
            let extensions = request.valueForHTTPHeaderField(HTTPHeaderFields.SecWebSocketExtensions)
            if version == HTTPHeaderValues.Version && key != nil && extensions == nil {
                return .Request(request)
            }
        }
        return .Invalid
    }
    
}
