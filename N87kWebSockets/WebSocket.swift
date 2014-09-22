//
//  WebSocket.swift
//  WebSockets
//
//  Created by jacob berkman on 9/20/14.
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

import N87kSwiftSupport

public enum Scheme: String {
    case WS = "ws"
    case WSS = "wss"

    public var isSecure: Bool { return self == WSS }
    public var defaultPort: Int { return self == WS ? 80 : 443 }
}

public protocol WebSocketDelegate: NSObjectProtocol {
    func webSocketDidOpen(webSocket: WebSocket)
    func webSocketDidClose(webSocket: WebSocket)
    func webSocket(webSocket: WebSocket, didFailWithError error: NSError)
}

public class WebSocket: NSObject {

    private enum State {
        case Connecting, Open, Closing, Closed
    }
    private var state: State = .Connecting {
        didSet {
            switch state {
            case .Connecting:
                expectedAccept = nil
            default:
                break
            }
        }
    }

    private var _currentRequest: NSURLRequest

    private var delegate: WebSocketDelegate?

    public let originalRequest: NSURLRequest
    public var currentRequest: NSURLRequest { return _currentRequest }
    private var scheme: Scheme? {
        return currentRequest.URL.scheme != nil ? Scheme.fromRaw(currentRequest.URL.scheme!) : nil
    }

    public let subprotocols: [String]

    private var inputStream: DataInputStream?
    private var response: CFHTTPMessageRef?
    private var inputBuffer: NSMutableData?
    private var expectedAccept: NSString?

    private var outputStream: DataOutputStream?

    public init(request: NSURLRequest, subprotocols: [String], delegate: WebSocketDelegate) {
        originalRequest = request
        _currentRequest = request
        self.subprotocols = subprotocols

        super.init()
        self.delegate = delegate

        connect()
    }

    public convenience init(request: NSURLRequest, subprotocol: String, delegate: WebSocketDelegate) {
        self.init(request: request, subprotocols: [subprotocol], delegate: delegate)
    }

    public convenience init(request: NSURLRequest, delegate: WebSocketDelegate) {
        self.init(request: request, subprotocols: [String](), delegate: delegate)
    }
}

extension WebSocket {
    private class func generateKey() -> String? {
        let keyLength = 16
        let data = NSMutableData(length: keyLength)
        if SecRandomCopyBytes(kSecRandomDefault, UInt(keyLength), UnsafeMutablePointer<UInt8>(data.mutableBytes)) != 0 {
            return nil
        }
        return data.base64EncodedStringWithOptions(nil)
    }
}

extension WebSocket {

    private struct Const {
        static let HTTPVersion: NSString = "HTTP/1.1"
        static let GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        static let UpgradeStatusCode = 101
    }

    private struct HeaderKeys {
        static let Connection: NSString = "Connection"
        static let Host: NSString = "Host"
        static let SecWebSocketAccept: NSString = "Sec-WebSocket-Accept"
        static let SecWebSocketKey: NSString = "Sec-WebSocket-Key"
        static let SecWebSocketVersion: NSString = "Sec-WebSocket-Version"
        static let Upgrade: NSString = "Upgrade"
    }

    private struct HeaderValues {
        static let Upgrade: NSString = "Upgrade"
        static let Version: NSString = "13"
        static let WebSocket: NSString = "WebSocket"
    }

    @objc private func delegateErrorTimerDidFire(timer: NSTimer) {
        delegate?.webSocket(self, didFailWithError: timer.userInfo as NSError)
    }

    private func connect() {
        if state != .Connecting {
            return
        }

        if currentRequest.URL.host == nil || scheme == nil || currentRequest.HTTPMethod != "GET" {
            state = .Closed
            let error = NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadURL, userInfo: nil)
            NSTimer.scheduledTimerWithTimeInterval(0, target: self, selector: "delegateErrorTimerDidFire", userInfo: error, repeats: false)
            return
        }

        let port = currentRequest.URL.port?.integerValue ?? scheme!.defaultPort
        var input: NSInputStream?
        var output: NSOutputStream?
        NSStream.getStreamsToHostWithName(currentRequest.URL.host!, port: port, inputStream: &input, outputStream: &output)
        if input == nil || output == nil {
            NSLog("Could not open streams")
            return
        }

        let securityLevel = scheme!.isSecure ? NSStreamSocketSecurityLevelTLSv1 : NSStreamSocketSecurityLevelNone
        input!.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)
        output!.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)

        input!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        output!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)

        inputStream = DataInputStream(inputStream: input!)
        outputStream = DataOutputStream(outputStream: output!)

        inputStream!.delegate = self
        outputStream!.delegate = self

        input!.open()
        output!.open()

        writeHandshake()
    }

    private func writeHandshake() {
        let key = WebSocket.generateKey()
        if key == nil {
            NSLog("Could not generate random key");
            // FIXME
            return
        }

        expectedAccept = "\(key!)\(Const.GUID)".N87k_SHA1Digest
        let port = currentRequest.URL.port != nil && currentRequest.URL.port != scheme!.defaultPort ? ":\(currentRequest.URL.port!)" : ""

        let request = CFHTTPMessageCreateRequest(kCFAllocatorDefault, "GET", NSURL(string: "http://off.net:8080"), "HTTP/1.1").takeRetainedValue()
        let headers: [NSString: NSString] = [
            HeaderKeys.Host: "\(currentRequest.URL.host!)\(port)",
            HeaderKeys.Connection: HeaderValues.Upgrade,
            HeaderKeys.Upgrade: HeaderValues.WebSocket,
            HeaderKeys.SecWebSocketVersion: HeaderValues.Version,
            HeaderKeys.SecWebSocketKey: key!
        ]
        for (k, v) in headers {
            CFHTTPMessageSetHeaderFieldValue(request, k, v)
        }

        if let data = CFHTTPMessageCopySerializedMessage(request)?.takeRetainedValue() {
            outputStream!.writeData(data)
        } else {
            //FIXME: Handle error
            NSLog("Could not serialize request")
        }
    }

    private func hasHeaderNamed(header: NSString, withValue value: NSString) -> Bool {
        if let headerValue = CFHTTPMessageCopyHeaderFieldValue(response, header)?.takeRetainedValue() {
            return value.caseInsensitiveCompare(headerValue as NSString) == NSComparisonResult.OrderedSame
        }
        return false
    }

    private func readHandshakeData(data: NSData) {
        if response == nil {
            response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, Boolean(0)).takeRetainedValue()
        }
        CFHTTPMessageAppendBytes(response, UnsafePointer<UInt8>(data.bytes), data.length)
        if CFHTTPMessageIsHeaderComplete(response) == Boolean(0) {
            return
        }

        if CFHTTPMessageCopyVersion(response)?.takeRetainedValue() != Const.HTTPVersion ||
            CFHTTPMessageGetResponseStatusCode(response) != Const.UpgradeStatusCode ||
            !hasHeaderNamed(HeaderKeys.Connection, withValue: HeaderValues.Upgrade) ||
            !hasHeaderNamed(HeaderKeys.Upgrade, withValue: HeaderValues.WebSocket) ||
            !hasHeaderNamed(HeaderKeys.SecWebSocketAccept, withValue: expectedAccept!) {
                //FIXME: handle error
                NSLog("Invalid response received:\n%@", NSString(data: data, encoding: NSASCIIStringEncoding))
                return
        }

        let data = CFHTTPMessageCopyBody(response)?.takeRetainedValue()
        response = nil
        state = .Open
        delegate?.webSocketDidOpen(self)
        if data != nil {
            readData(data!)
        }
    }

    private func readData(data: NSData) {
        if inputBuffer == nil {
            inputBuffer = NSMutableData(data: data)
        } else {
            inputBuffer?.appendData(data)
        }
        NSLog("Have %@ bytes of data", "\(inputBuffer!.length)")
    }

}

extension WebSocket: DataInputStreamDelegate {

    func dataInputStream(dataInputStream: DataInputStream, didReadData data: NSData) {
        switch state {
        case .Connecting:
            readHandshakeData(data)
        case .Open:
            readData(data)
        default:
            break
        }
    }

    func dataInputStream(dataInputStream: DataInputStream, didCloseWithError error: NSError) {
        NSLog("%@ %@", __FUNCTION__, error)
    }

    func dataInputStreamDidReadToEnd(dataInputStream: DataInputStream) {
        NSLog("%@", __FUNCTION__)
    }

}

extension WebSocket: DataOutputStreamDelegate {

    func dataOutputStream(dataOutputStream: DataOutputStream, didCloseWithError error: NSError) {
        NSLog("%@ %@", __FUNCTION__, error)
    }

}
