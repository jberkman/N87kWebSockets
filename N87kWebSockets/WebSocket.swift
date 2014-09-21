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

    private var input: NSInputStream?
    private var output: NSOutputStream?

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
    @objc private func delegateErrorTimerDidFire(timer: NSTimer) {
        delegate?.webSocket(self, didFailWithError: timer.userInfo as NSError)
    }
}

extension WebSocket {

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
        NSStream.getStreamsToHostWithName(currentRequest.URL.host!, port: port, inputStream: &input, outputStream: &output)

        input?.delegate = self
        output?.delegate = self

        let securityLevel = scheme!.isSecure ? NSStreamSocketSecurityLevelTLSv1 : NSStreamSocketSecurityLevelNone
        input?.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)
        output?.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)

        input?.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        output?.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)

        input?.open()
        output?.open()
    }

}

extension WebSocket {

    private func generateKey() -> String? {
        let keyLength = 16
        let bytes = UnsafeMutablePointer<UInt8>.alloc(keyLength)
        if SecRandomCopyBytes(kSecRandomDefault, UInt(keyLength), bytes) != 0 {
            bytes.dealloc(keyLength)
            return nil
        }
        let data = NSData(bytesNoCopy: UnsafeMutablePointer<Void>(bytes), length: keyLength)
        let ret = data.base64EncodedStringWithOptions(nil)
        bytes.destroy()
        return ret
    }

    private func sendHandshake() {
        let URL = NSURLComponents(URL: currentRequest.URL, resolvingAgainstBaseURL: true)
        let host = URL.percentEncodedHost!
        var resource = URL.percentEncodedPath ?? ""
        if resource == "" {
            resource = "/"
        }
        if let query = URL.percentEncodedQuery {
            resource = "\(resource)?\(query)"
        }

        key = generateKey()
        if key == nil {
            NSLog("Could not get random bytes");
            // FIXME
            return
        }

        let handshake = join("\r\n", [
            "GET \(resource) HTTP/1.1",
            "Connection: Upgrade",
            "Host: \(host)",
            "Sec-WebSocket-Key: \(key!)",
            "Sec-WebSocket-Version: 13",
            "Upgrade: websocket",
            "", ""])
        NSLog("writing handshake: \n%@", handshake)

        let bytesWritten = output!.write(handshake, maxLength: handshake.lengthOfBytesUsingEncoding(NSASCIIStringEncoding))
        NSLog("Wrote %@ bytes.", "\(bytesWritten)")
    }
}

extension WebSocket {
    func readData() {
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<UInt8>.alloc(bufferSize)
        let bytesRead = input!.read(buffer, maxLength: bufferSize)
        if bytesRead < 0 {
            NSLog("Error reading from input")
            return
        }
        let data = NSData(bytesNoCopy: UnsafeMutablePointer<Void>(buffer), length: bytesRead > 0 ? bytesRead : bufferSize)
        let response = NSString(data: data, encoding: NSASCIIStringEncoding)
        buffer.destroy()
        NSLog("Got response:\n%@", response)
    }
}

extension WebSocket: NSStreamDelegate {
    public func stream(stream: NSStream, handleEvent streamEvent: NSStreamEvent) {
        if streamEvent & .ErrorOccurred == .ErrorOccurred {
            NSLog("Error occurred: %@", stream.streamError!)
        }
        if streamEvent & .HasSpaceAvailable == .HasSpaceAvailable && stream == output {
            if key == nil {
                sendHandshake()
            }
        }
        if streamEvent & .HasBytesAvailable == .HasBytesAvailable && stream == input {
            readData()
        }
    }
}

public protocol WebSocketDelegate: NSObjectProtocol {
    func webSocketDidOpen(webSocket: WebSocket)
    func webSocketDidClose(webSocket: WebSocket)
    func webSocket(webSocket: WebSocket, didFailWithError error: NSError)
}
