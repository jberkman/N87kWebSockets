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

@objc
public protocol WebSocketDelegate: NSObjectProtocol {
    func webSocketDidOpen(webSocket: WebSocket)
    func webSocketDidClose(webSocket: WebSocket)
    func webSocket(webSocket: WebSocket, didFailWithError error: NSError)
    
    func webSocket(webSocket: WebSocket, willBeginDataWithBinary isBinary: Bool)
    func webSocket(webSocket: WebSocket, didReadData data: NSData)
    func webSocketDidFinishData(webSocket: WebSocket)
    
    optional func webSocketDidPing(webSocket: WebSocket)
    optional func webSocketDidPong(webSocket: WebSocket)
}

public class WebSocket: NSObject {

    private enum State {
        case ClientConnecting(ClientHandshake)
        case ServerConnecting(ServerHandshake)
        case Open(tokenizer: FrameTokenizer, serializer: FrameSerializer, forwardData: Bool, isFinal: Bool)
        case Closing, Closed
    }

    private var scheme: Scheme?
    private var state: State = .Closed {
        didSet {
            switch (oldValue, state) {
            case (.ClientConnecting, .Open):
                delegate?.webSocketDidOpen(self)
            default:
                break
            }
        }
    }
    private var runLoop: NSRunLoop?

    private var _currentRequest: NSURLRequest? {
        didSet {
            if let requestScheme = _currentRequest?.URL.scheme {
                scheme = Scheme(rawValue: requestScheme)
            } else {
                scheme = nil
            }
        }
    }

    private var delegate: WebSocketDelegate?

    public let originalRequest: NSURLRequest?
    public var currentRequest: NSURLRequest? { return _currentRequest }

    public let subprotocols: [String]

    private var inputStream: DataInputStream!
    private var outputStream: DataOutputStream!

    public init(request: NSURLRequest, subprotocols: [String], delegate: WebSocketDelegate) {
        originalRequest = request
        _currentRequest = request
        if let scheme = request.URL.scheme {
            self.scheme = Scheme(rawValue: scheme)
        }
        self.subprotocols = subprotocols

        super.init()
        self.delegate = delegate

        connect()
    }
    
    public init(scheme: Scheme, inputStream: NSInputStream, outputStream: NSOutputStream, runLoop: NSRunLoop, delegate: WebSocketDelegate) {
        self.scheme = scheme
        subprotocols = []
        self.runLoop = runLoop
        self.delegate = delegate
        super.init()
        initializeInputStream(inputStream, outputStream: outputStream)
        state = .ServerConnecting(ServerHandshake())
    }

    public convenience init(request: NSURLRequest, subprotocol: String, delegate: WebSocketDelegate) {
        self.init(request: request, subprotocols: [subprotocol], delegate: delegate)
    }

    public convenience init(request: NSURLRequest, delegate: WebSocketDelegate) {
        self.init(request: request, subprotocols: [String](), delegate: delegate)
    }

    public func writeText(text: String) -> Bool {
        switch state {
        case .Open(_, let serializer, _, _):
            if let data = text.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false) {
                if let header = serializer.beginFrameWithOpCode(.Text, isFinal: true, length: UInt64(data.length)) {
                    outputStream.writeData(header)
                    outputStream.writeData(originalRequest == nil ? data : serializer.maskedData(data))
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
        switch state {
        case .Closed where currentRequest != nil:
            if currentRequest?.URL.host == nil || scheme == nil || currentRequest?.HTTPMethod != "GET" {
                let error = NSError(domain: NSCocoaErrorDomain, code: NSURLErrorBadURL, userInfo: nil)
                NSTimer.scheduledTimerWithTimeInterval(0, target: self, selector: "delegateErrorTimerDidFire:", userInfo: error, repeats: false)
                return
            }

            let port = currentRequest!.URL.port?.integerValue ?? scheme!.defaultPort
            var input: NSInputStream?
            var output: NSOutputStream?
            NSStream.getStreamsToHostWithName(currentRequest!.URL.host!, port: port, inputStream: &input, outputStream: &output)
            if input == nil || output == nil {
                NSLog("Could not open streams")
                return
            }

            let handshake = ClientHandshake(request: currentRequest!)
            let data: NSData! = handshake.requestData
            if data == nil {
                NSLog("Could not get handshake request data.")
                return
            }
            
            initializeInputStream(input!, outputStream: output!)
            
            state = .ClientConnecting(handshake)
            outputStream.writeData(data)
            
        default:
            break
        }
    }
    
    func initializeInputStream(input: NSInputStream, outputStream output: NSOutputStream) {
        let securityLevel = scheme!.isSecure ? NSStreamSocketSecurityLevelTLSv1 : NSStreamSocketSecurityLevelNone
        input.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)
        output.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)

        let runLoop = self.runLoop ?? NSRunLoop.currentRunLoop()
        input.scheduleInRunLoop(runLoop, forMode: NSDefaultRunLoopMode)
        output.scheduleInRunLoop(runLoop, forMode: NSDefaultRunLoopMode)

        inputStream = DataInputStream(inputStream: input)
        outputStream = DataOutputStream(outputStream: output)

        inputStream.delegate = self
        outputStream.delegate = self

        input.open()
        output.open()
    }

    private func handleClientHandshake(result: ClientHandshake.Result) {
        switch result {
        case .Incomplete:
            break

        case .Invalid:
            // FIXME: Notify delegate of error
            NSLog("Invalid handshake.")

        case .Response(let response, let data):
            let tokenizer = FrameTokenizer(masked: false)
            tokenizer.delegate = self
            state = .Open(tokenizer: tokenizer, serializer: FrameSerializer(masked: true), forwardData: false, isFinal: false)
            if data != nil {
                handleTokenizerError(tokenizer.readData(data!))
            }
        }
    }

    private func handleServerHandshake(handshake: ServerHandshake, result: ServerHandshake.Result) {
        switch result {
        case .Incomplete:
            break
            
        case .Invalid:
            // FIXME: Notify delegate of error
            NSLog("Invalid handshake.")
            
        case .Request(let request, let data):
            // FIXME: Validate request
            let responseData = handshake.responseData
            if responseData != nil {
                outputStream.writeData(responseData!)
                let tokenizer = FrameTokenizer(masked: true)
                tokenizer.delegate = self
                state = .Open(tokenizer: tokenizer, serializer: FrameSerializer(masked: false), forwardData: false, isFinal: false)
                if data != nil {
                    handleTokenizerError(tokenizer.readData(data!))
                }
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
        case .ClientConnecting(let handshake):
            handleClientHandshake(handshake.readData(data))
        case .ServerConnecting(let handshake):
            NSLog("%@", "read \(data.length)")
            handleServerHandshake(handshake, result: handshake.readData(data))
        case .Open(let tokenizer, _, _, _):
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
        var isBinary = false
        switch state {
        case .Open(let tokenizer, let serializer, let forwardData, _):
            switch opCode {
            case .Binary where !forwardData:
                isBinary = true
                fallthrough
            case .Text where !forwardData:
                delegate?.webSocket(self, willBeginDataWithBinary: isBinary)
                state = .Open(tokenizer: tokenizer, serializer: serializer, forwardData: true, isFinal: isFinal)
            case .Continuation where forwardData:
                break
            case .Ping where isFinal:
                delegate?.webSocketDidPing?(self)
                if let data = serializer.beginFrameWithOpCode(.Pong, isFinal: true, length: 0) {
                    outputStream.writeData(data)
                }
            case .Pong where isFinal:
                delegate?.webSocketDidPong?(self)
            default:
                NSLog("Invalid opCode for state.");
            }

        default:
            NSLog("Invalid state for opCode")
        }
    }

    func frameTokenizer(frameTokenizer: FrameTokenizer, didReadData data: NSData) {
        NSLog("%@ %@", __FUNCTION__, data)
        switch state {
        case .Open(_, _, true, _):
            delegate?.webSocket(self, didReadData: data)
        default:
            break
        }
    }

    func frameTokenizerDidEndFrame(frameTokenizer: FrameTokenizer) {
        NSLog("Ended frame.")
        switch state {
        case .Open(let tokenizer, let serializer, true, true):
            delegate?.webSocketDidFinishData(self)
            state = .Open(tokenizer: tokenizer, serializer: serializer, forwardData: false, isFinal: false)
        default:
            break
        }
    }

}
