//
//  NSURLRequestAdditions.swift
//  N87kWebSockets
//
//  Created by jacob berkman on 10/31/14.
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

extension NSMutableURLRequest {

    convenience init?(N87k_HTTPMessage HTTPMessage: CFHTTPMessage) {
        if (CFHTTPMessageCopyVersion(HTTPMessage)?.takeRetainedValue() as? String) == kCFHTTPVersion1_1 as String {
            if let URL: NSURL = CFHTTPMessageCopyRequestURL(HTTPMessage)?.takeRetainedValue() {
                self.init(URL: URL)
                HTTPMethod = CFHTTPMessageCopyRequestMethod(HTTPMessage)?.takeRetainedValue() as? String ?? "GET"
                allHTTPHeaderFields = CFHTTPMessageCopyAllHeaderFields(HTTPMessage)?.takeRetainedValue() as? [NSObject: AnyObject]
                HTTPBody = CFHTTPMessageCopyBody(HTTPMessage)?.takeRetainedValue()
                return
            }
        }
        self.init(URL: NSURL(string: "http://host.test")!)
        return nil
    }

}

extension NSURLRequest {

    var N87k_serializedData: NSData? {

        let requestMessage = CFHTTPMessageCreateRequest(kCFAllocatorDefault, HTTPMethod!, URL, kCFHTTPVersion1_1).takeRetainedValue()

        let host = URL!.host! + (URL!.port != nil ? ":\(URL!.port!)" : "")
        CFHTTPMessageSetHeaderFieldValue(requestMessage, "Host", host)
        if let requestHeaders = allHTTPHeaderFields as? [NSString: NSString] {
            for (k, v) in requestHeaders {
                CFHTTPMessageSetHeaderFieldValue(requestMessage, k, v)
            }

        }

        return CFHTTPMessageCopySerializedMessage(requestMessage)?.takeRetainedValue()
    }

    public var N87k_webSocketRequest: Bool {
        let connection = valueForHTTPHeaderField(HTTPHeaderFields.Connection)?.lowercaseString
        let upgrade = valueForHTTPHeaderField(HTTPHeaderFields.Upgrade)?.lowercaseString
        return connection == HTTPHeaderValues.Upgrade.lowercaseString && upgrade == HTTPHeaderValues.WebSocket.lowercaseString
    }
   
}
