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
        case Request(NSURLRequest, NSData?)
    }
    
    private let requestMessage = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, Boolean(1)).takeRetainedValue()
    private var key: String?
    private var expectedAccept: String {
        return "\(key!)\(GUIDs.WebSocket)".N87k_SHA1Digest
    }

    var responseData: NSData? {
        let statusCode = HTTPStatusCodes.Upgrade
        let responseMessage = CFHTTPMessageCreateResponse(kCFAllocatorDefault, statusCode, NSHTTPURLResponse.localizedStringForStatusCode(statusCode) as NSString, HTTPVersions.HTTP1_1).takeRetainedValue()
        let headers: [NSString: NSString] = [
            HTTPHeaderFields.Connection: HTTPHeaderValues.Upgrade,
            HTTPHeaderFields.Upgrade: HTTPHeaderValues.WebSocket,
            HTTPHeaderFields.SecWebSocketVersion: HTTPHeaderValues.Version,
            HTTPHeaderFields.SecWebSocketAccept: expectedAccept
        ]
        for (headerField, value) in headers {
            CFHTTPMessageSetHeaderFieldValue(responseMessage, headerField, value)
        }
        return CFHTTPMessageCopySerializedMessage(responseMessage).takeRetainedValue()
    }
    
    func readData(data: NSData) -> Result {
        CFHTTPMessageAppendBytes(requestMessage, UnsafePointer<UInt8>(data.bytes), data.length)
        if CFHTTPMessageIsHeaderComplete(requestMessage) == Boolean(0) {
            return .Incomplete
        }
        
        var response: NSHTTPURLResponse?
        var responseData: NSData?
        if HTTPVersions.HTTP1_1 != CFHTTPMessageCopyVersion(requestMessage)?.takeRetainedValue() ||
            "GET" as NSString != CFHTTPMessageCopyRequestMethod(requestMessage)?.takeRetainedValue() {
        } else if let headerFields: NSDictionary = CFHTTPMessageCopyAllHeaderFields(requestMessage)?.takeRetainedValue() {
            if headerFields[HTTPHeaderFields.Connection]?.lowercaseString != HTTPHeaderValues.Upgrade.lowercaseString ||
                headerFields[HTTPHeaderFields.Upgrade]?.lowercaseString != HTTPHeaderValues.WebSocket.lowercaseString ||
                headerFields[HTTPHeaderFields.SecWebSocketVersion]?.lowercaseString != HTTPHeaderValues.Version ||
                headerFields[HTTPHeaderFields.SecWebSocketKey] == nil ||
                headerFields[HTTPHeaderFields.SecWebSocketExtensions] != nil {
            } else if let URL: NSURL = CFHTTPMessageCopyRequestURL(requestMessage)?.takeRetainedValue() {
                let request = NSMutableURLRequest(URL: URL)
                request.HTTPMethod = "GET"
                for (k, v) in headerFields {
                    request.setValue(v as NSString, forHTTPHeaderField: k as NSString)
                }
                key = headerFields[HTTPHeaderFields.SecWebSocketKey] as? NSString
                let requestData = CFHTTPMessageCopyBody(requestMessage)?.takeRetainedValue() as? AnyObject as? NSData
                return .Request(request, requestData)
            }
        }
        return .Invalid
    }
    
}
