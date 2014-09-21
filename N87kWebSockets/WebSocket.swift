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
    private var state = State.Connecting

    private var _currentRequest: NSURLRequest

    private var delegate: WebSocketDelegate?

    public let originalRequest: NSURLRequest
    public var currentRequest: NSURLRequest { return _currentRequest }

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

        let URL = currentRequest.URL
        let scheme = URL.scheme != nil ? Scheme.fromRaw(URL.scheme!) : nil

        if URL.host == nil || scheme == nil {
            state = .Closed
            let error = NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadURL, userInfo: nil)
            NSTimer.scheduledTimerWithTimeInterval(0, target: self, selector: "delegateErrorTimerDidFire", userInfo: error, repeats: false)
            return
        }

        NSLog("Getting streams to %@...", "\(URL.host)")
        NSStream.getStreamsToHostWithName(URL.host!, port: URL.port?.integerValue ?? scheme!.defaultPort, inputStream: &input, outputStream: &output)
        NSLog("Done: %@ %@", "\(input)", "\(output)")
    }
}

public protocol WebSocketDelegate: NSObjectProtocol {
    func webSocketDidOpen(webSocket: WebSocket)
    func webSocketDidClose(webSocket: WebSocket)
    func webSocket(webSocket: WebSocket, didFailWithError error: NSError)
}
