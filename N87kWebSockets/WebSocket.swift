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

public protocol WebSocketDelegate: NSObjectProtocol {
    func webSocketDidOpen(webSocket: WebSocket)
    func webSocketDidClose(webSocket: WebSocket)
    func webSocket(webSocket: WebSocket, didFailWithError error: NSError)
}

public class WebSocket: NSObject {

    private enum State {
        case Connecting(handshake: ClientHandshake)
        case Open(tokenizer: FrameTokenizer, serializer: FrameSerializer)
        case Closing, Closed
    }
    private var state: State = .Closed {
        didSet {
            switch state {
            case .Open:
                delegate?.webSocketDidOpen(self)
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
        return currentRequest.URL.scheme != nil ? Scheme(rawValue: currentRequest.URL.scheme!) : nil
    }

    public let subprotocols: [String]

    private var inputStream: DataInputStream!
    private var outputStream: DataOutputStream!

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

    public func writeText(text: String) -> Bool {
        switch state {
        case .Open(_, let serializer):
            if let data = text.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false) {
                if let header = serializer.beginFrameWithOpCode(.Text, isFinal: true, length: UInt64(data.length)) {
                    outputStream.writeData(header)
                    outputStream.writeData(serializer.maskedData(data))
                    return true
                }
            }
            return false
        default:
            fatalError("Can't write text unless open")
        }
    }
}

extension WebSocket {

    @objc private func delegateErrorTimerDidFire(timer: NSTimer) {
        delegate?.webSocket(self, didFailWithError: timer.userInfo as NSError)
    }

    private func connect() {
        if state != .Closed {
            return
        }

        if currentRequest.URL.host == nil || scheme == nil || currentRequest.HTTPMethod != "GET" {
            let error = NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadURL, userInfo: nil)
            NSTimer.scheduledTimerWithTimeInterval(0, target: self, selector: "delegateErrorTimerDidFire", userInfo: error, repeats: false)
            return
        }

        let port = currentRequest.URL.port?.integerValue ?? scheme!.defaultPort
        var input: NSInputStream!
        var output: NSOutputStream!
        NSStream.getStreamsToHostWithName(currentRequest.URL.host!, port: port, inputStream: &input, outputStream: &output)
        if input == nil || output == nil {
            NSLog("Could not open streams")
            return
        }

        let handshake = ClientHandshake(request: currentRequest)
        let data: NSData! = handshake.requestData
        if data == nil {
            NSLog("Could not get handshake request data.")
            return
        }
        
        let securityLevel = scheme!.isSecure ? NSStreamSocketSecurityLevelTLSv1 : NSStreamSocketSecurityLevelNone
        input.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)
        output.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)

        input.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        output.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)

        inputStream = DataInputStream(inputStream: input)
        outputStream = DataOutputStream(outputStream: output)

        inputStream.delegate = self
        outputStream.delegate = self

        input.open()
        output.open()

        state = .Connecting(handshake: handshake)
        outputStream!.writeData(data)
    }

    private func handleHandshakeResult(result: ClientHandshake.Result) {
        switch result {
        case .Incomplete:
            break

        case .Invalid:
            // FIXME: Notify delegate of error
            NSLog("Invalid handshake.")

        case .Response(let response, let data):
            let tokenizer = FrameTokenizer(masked: false)
            tokenizer.delegate = self
            state = .Open(tokenizer: tokenizer, serializer: FrameSerializer(masked: true))
            if data != nil {
                handleTokenizerError(tokenizer.readData(data))
            }
        }
    }

    private func handleTokenizerError(error: NSError?) {
        if error != nil {
            NSLog("Invalid data: %@", error!)
        }
    }

}

extension WebSocket: DataInputStreamDelegate {

    func dataInputStream(dataInputStream: DataInputStream, didReadData data: NSData) {
        switch state {
        case .Connecting(let handshake):
            handleHandshakeResult(handshake.readData(data))
        case .Open(let tokenizer, let serializer):
            handleTokenizerError(tokenizer.readData(data))
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

extension WebSocket: FrameTokenizerDelegate {

    func frameTokenizer(frameTokenizer: FrameTokenizer, didBeginFrameWithOpCode opCode: OpCode, isFinal: Bool, reservedBits: (Bit, Bit, Bit)) {
        NSLog("Got frame with opCode: %@", "\(opCode.rawValue)")
        if opCode == OpCode.Text {
            inputBuffer = NSMutableData()
        }
    }

    func frameTokenizer(frameTokenizer: FrameTokenizer, didReadData data: NSData) {
        inputBuffer?.appendData(data)
    }

    func frameTokenizerDidEndFrame(frameTokenizer: FrameTokenizer) {
        NSLog("Ended frame.")
        if inputBuffer != nil {
            let text: NSString? = NSString(data: inputBuffer!, encoding: NSUTF8StringEncoding)
            if text != nil {
                NSLog("Got text: %@", text!)
            }
            inputBuffer = nil
        }
    }

}
