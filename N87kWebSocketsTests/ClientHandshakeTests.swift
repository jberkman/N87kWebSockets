//
//  ClientHandshakeTests.swift
//  N87kWebSockets
//
//  Created by jacob berkman on 2014-10-07.
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

import XCTest
import CFNetwork

class ClientHandshakeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testNilHost() {
        let URL = NSURL(scheme: Scheme.WS.rawValue, host: nil, path: "/path")!
        let request = NSURLRequest(URL: URL)
        XCTAssertNil(ClientHandshake(request: request))
    }

    func testPost() {
        let URL = NSURL(scheme: Scheme.WS.rawValue, host: "host", path: "/path")!
        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = "POST"
        XCTAssertNil(ClientHandshake(request: request))
    }
    
    func testInvalidScheme() {
        let URL = NSURL(scheme: "http", host: "host", path: "/path")!
        let request = NSURLRequest(URL: URL)
        XCTAssertNil(ClientHandshake(request: request))
    }
    
    func testValidURL() {
        let URL = NSURL(scheme: Scheme.WS.rawValue, host: "host", path: "/path")!
        let request = NSURLRequest(URL: URL)
        let handshake = ClientHandshake(request: request)
        XCTAssertNotNil(handshake)
    }
    
    func testRequest() {
        let URL = NSURL(scheme: Scheme.WS.rawValue, host: "host", path: "/path")!
        let request = NSURLRequest(URL: URL)
        let handshake = ClientHandshake(request: request)
        XCTAssertNotNil(handshake)

        let data = handshake?.requestData
        XCTAssertNotNil(data)
        
        if let data = data {
            dlog("%@", NSString(data: data, encoding: NSUTF8StringEncoding)!)
            let request = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, Boolean(1)).takeRetainedValue()
            CFHTTPMessageAppendBytes(request, UnsafePointer<UInt8>(data.bytes), data.length)
            XCTAssertEqual(CFHTTPMessageIsHeaderComplete(request), Boolean(1))
            
            let method = CFHTTPMessageCopyRequestMethod(request).takeRetainedValue() as NSString
            XCTAssertEqual(method, "GET")
            
            let requestURL = CFHTTPMessageCopyRequestURL(request).takeRetainedValue() as NSURL
            XCTAssertEqual(requestURL.absoluteString!, "http://host/path")
            
            let headers = CFHTTPMessageCopyAllHeaderFields(request).takeRetainedValue() as NSDictionary
            func assertHeader(key: String, value: NSString) {
                let header = headers[key] as? NSString
                XCTAssertNotNil(header, "nil \(key) header")
                if let header = header {
                    XCTAssertEqual(header, value, "incorrect value for \(key) header")
                }
            }
            
            assertHeader("Host", "host")
            assertHeader("Connection", "Upgrade")
            assertHeader("Upgrade", "websocket")
            assertHeader("Sec-WebSocket-Version", "13")

            let key = headers["Sec-WebSocket-Key"] as? NSString
            XCTAssertNotNil(key)
        }
    }

    func testIncompleteResponse() {
        let URL = NSURL(scheme: Scheme.WS.rawValue, host: "host", path: "/path")!
        let request = NSURLRequest(URL: URL)
        let handshake = ClientHandshake(request: request)

        let response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 101, "Connection upgrade", "HTTP/1.1").takeRetainedValue()
        let data = CFHTTPMessageCopySerializedMessage(response).takeRetainedValue() as NSData

        let status = handshake?.readData(NSData(bytes: UnsafePointer<UInt8>(data.bytes), length: data.length / 2))
        switch status {
        case .Some(.Incomplete):
            break
        default:
            XCTFail("Invalid handshake status: \(status)")
        }
    }
}
