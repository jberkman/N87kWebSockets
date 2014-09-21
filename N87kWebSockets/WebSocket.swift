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

import Foundation
import Security

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
                key = nil
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
    private var outputStream: DataOutputStream?

    private var key: String?

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

}

extension WebSocket {

    private func writeHandshake() {
        if let newKey = WebSocket.generateKey() {
            key = newKey
        } else {
            NSLog("Could not generate random key");
            // FIXME
            return
        }

        let URL = NSURLComponents(URL: currentRequest.URL, resolvingAgainstBaseURL: true)

        let host = URL.percentEncodedHost!
        let port = URL.port != nil && URL.port != scheme!.defaultPort ? ":\(URL.port!)" : ""

        var path: String
        if let encodedPath = URL.percentEncodedPath {
            path = !encodedPath.isEmpty ? encodedPath : "/"
        } else {
            path = "/"
        }

        var query: String
        if let encodedQuery = URL.percentEncodedQuery {
            query = "?\(encodedQuery)"
        } else {
            query = ""
        }

        let handshake = join("\r\n", [
            "GET \(path)\(query) HTTP/1.1",
            "Connection: Upgrade",
            "Host: \(host)\(port)",
            "Sec-WebSocket-Key: \(key!)",
            "Sec-WebSocket-Version: 13",
            "Upgrade: websocket",
            "", ""])
        NSLog("sending handshake: \n%@", handshake)

        if let data = (handshake as NSString).dataUsingEncoding(NSASCIIStringEncoding) {
            outputStream?.writeData(data)
        } else {
            // FIXME: handle error
            NSLog("Could not encode handshake.")
        }
    }

}

extension WebSocket: DataInputStreamDelegate {

    func dataInputStream(dataInputStream: DataInputStream, didReadData data: NSData) {
        NSLog("%@\n%@", __FUNCTION__, NSString(data: data, encoding: NSASCIIStringEncoding))
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
