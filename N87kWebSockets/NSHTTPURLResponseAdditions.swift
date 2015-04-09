//
//  NSHTTPURLResponseAdditions.swift
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

extension NSHTTPURLResponse {

    convenience init?(N87k_URL URL: NSURL, HTTPMessage: CFHTTPMessage) {
        if let HTTPVersion: NSString = CFHTTPMessageCopyVersion(HTTPMessage)?.takeRetainedValue() {
            if let headerFields: NSDictionary = CFHTTPMessageCopyAllHeaderFields(HTTPMessage)?.takeRetainedValue() {
                let statusCode = CFHTTPMessageGetResponseStatusCode(HTTPMessage)
                self.init(URL: URL, statusCode: statusCode, HTTPVersion: HTTPVersion as String, headerFields: headerFields as [NSObject : AnyObject])
                return
            }
        }
        self.init(URL: NSURL(string: "http://invalid")!, statusCode: 500, HTTPVersion: nil, headerFields: nil)
        return nil
    }


    var N87k_serializedData: NSData? {
        if let responseMessage = CFHTTPMessageCreateResponse(kCFAllocatorDefault, statusCode, nil, kCFHTTPVersion1_1)?.takeRetainedValue() {
            for (headerField, value) in allHeaderFields {
                CFHTTPMessageSetHeaderFieldValue(responseMessage, headerField as! NSString, value as! NSString)
            }
            return CFHTTPMessageCopySerializedMessage(responseMessage)?.takeRetainedValue()
        }
        return nil
    }

}
