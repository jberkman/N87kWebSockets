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
    optional func webSocket(webSocket: WebSocket, shouldAcceptConnectionWithRequest request: NSURLRequest) -> Bool

    func webSocketDidOpen(webSocket: WebSocket)
    func webSocket(webSocket: WebSocket, didCloseWithStatusCode statusCode: UInt16)
    func webSocket(webSocket: WebSocket, didCloseWithError error: NSError)
    
    func webSocketWillBeginTextData(webSocket: WebSocket)
    func webSocketWillBeginBinaryData(webSocket: WebSocket)
    func webSocket(webSocket: WebSocket, didReadData data: NSData)
    func webSocketDidFinishData(webSocket: WebSocket)
    
    optional func webSocketDidPing(webSocket: WebSocket)
    optional func webSocketDidPong(webSocket: WebSocket)
}

public class WebSocket: NSObject {

    private enum State {
        case ClientConnecting(ClientHandshake)
        case ServerConnecting(ServerHandshake)
        case Open(tokenizer: FrameTokenizer, serializer: FrameSerializer, opCode: OpCode?, isFinal: Bool?)
        case ClosingWithError(NSError)
        case ClosingWithStatusCode(UInt16)
        case Closed
    }

    private var scheme: Scheme?
    private var state: State = .Closed {
        didSet {
            switch (oldValue, state) {
            case (.ClientConnecting, .Open):
                delegate?.webSocketDidOpen(self)
            case (_, .ClosingWithError), (_, .ClosingWithStatusCode) where outputStream != nil:
                outputStream.close()
            case (_, .ClosingWithError), (_, .ClosingWithStatusCode) where outputStream == nil:
                state = .Closed
            case (.ClosingWithError(let error), .Closed):
                delegate?.webSocket(self, didCloseWithError: error)
            case (.ClosingWithStatusCode(let statusCode), .Closed):
                delegate?.webSocket(self, didCloseWithStatusCode: statusCode)
            default:
                break
            }
        }
    }

    private var runLoop: NSRunLoop?
    private var runLoopMode = NSDefaultRunLoopMode

    private var _currentRequest: NSURLRequest? {
        didSet {
            if let requestScheme = _currentRequest?.URL.scheme {
                scheme = Scheme(rawValue: requestScheme)
            } else {
                scheme = nil
            }
        }
    }

    public var delegate: WebSocketDelegate?

    public let originalRequest: NSURLRequest?
    public var currentRequest: NSURLRequest? { return _currentRequest }

    public let subprotocols: [String]

    private var inputStream: DataInputStream! {
        didSet {
            oldValue?.delegate = nil
            inputStream?.delegate = self
        }
    }
    
    private var outputStream: DataOutputStream! {
        didSet {
            oldValue?.delegate = nil
            outputStream?.delegate = self
        }
    }

    // Client API
    public init(request: NSURLRequest, subprotocols: [String] = []) {
        originalRequest = request
        _currentRequest = request
        if let scheme = request.URL.scheme {
            self.scheme = Scheme(rawValue: scheme)
        }
        self.subprotocols = subprotocols
        super.init()
    }
    
    // Server API
    public init(scheme: Scheme, subprotocols: [String] = []) {
        self.scheme = scheme
        self.subprotocols = subprotocols
        super.init()
    }
    
    deinit {
        inputStream = nil
        outputStream = nil
    }
    
    public func scheduleInRunLoop(runLoop: NSRunLoop, forMode mode: String) {
        self.runLoop = runLoop
        self.runLoopMode = mode
    }

    public func connect() {
        switch state {
        case .Closed where currentRequest != nil:
            if currentRequest!.URL.host == nil || scheme == nil || currentRequest!.HTTPMethod != "GET" {
                delegate?.webSocket(self, didCloseWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL, userInfo: nil))
                return
            }
            
            let port = currentRequest!.URL.port?.integerValue ?? scheme!.defaultPort
            var inputStream: NSInputStream?
            var outputStream: NSOutputStream?
            NSStream.getStreamsToHostWithName(currentRequest!.URL.host!, port: port, inputStream: &inputStream, outputStream: &outputStream)
            if inputStream == nil || outputStream == nil {
                delegate?.webSocket(self, didCloseWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil))
                return
            }
            
            connectWithInputStream(inputStream!, outputStream: outputStream!)
            
        default:
            break
        }
    }

    public func connectWithInputStream(inputStream: NSInputStream, outputStream: NSOutputStream) {
        if let handshake = ClientHandshake(request: currentRequest!) {
            if let data = handshake.requestData {
                initializeInputStream(inputStream, outputStream: outputStream)
                state = .ClientConnecting(handshake)
                self.outputStream.writeData(data)
                return
            }
        }
        state = .ClosingWithError(NSError(domain: ErrorDomain, code: Errors.InvalidHandshake.rawValue, userInfo: nil))
    }
    
    public func acceptConnectionWithInputStream(inputStream: NSInputStream, outputStream: NSOutputStream) {
        initializeInputStream(inputStream, outputStream: outputStream)
        state = .ServerConnecting(ServerHandshake())
    }
    
    public func writeText(text: String) -> Bool {
        if let data = text.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false) {
            return writeEncodedText(data)
        }
        return false
    }
    
    public func writeEncodedText(encodedText: NSData) -> Bool {
        switch state {
        case .Open(_, let serializer, _, _):
            if let header = serializer.beginFrameWithOpCode(.Text, isFinal: true, length: UInt64(encodedText.length)) {
                outputStream.writeData(header)
                outputStream.writeData(originalRequest == nil ? encodedText : serializer.maskedData(encodedText))
                return true
            }

        default:
            dlog("\(__FUNCTION__): Can't write text unless open")
        }
        return false
    }

    public func writeData(data: NSData) -> Bool {
        switch state {
        case .Open(_, let serializer, _, _):
            if let header = serializer.beginFrameWithOpCode(.Binary, isFinal: true, length: UInt64(data.length)) {
                outputStream.writeData(header)
                outputStream.writeData(originalRequest == nil ? data : serializer.maskedData(data))
                return true
            }

        default:
            dlog("\(__FUNCTION__): Can't write binary data unless open")
        }
        return false
    }
    
    public func ping(data: NSData? = nil) -> Bool {
        switch state {
        case .Open(_, let serializer, _, _):
            if let header = serializer.beginFrameWithOpCode(.Ping, isFinal: true, length: UInt64(data?.length ?? 0)) {
                outputStream.writeData(header)
                if data != nil {
                    outputStream.writeData(data!)
                }
                return true
            }

        default:
            dlog("\(__FUNCTION__): Can't ping unless open")
        }
        return false
    }

    public func closeWithStatusCode(statusCode: UInt16, message: String?) {
        switch state {
        case .Open(_, let serializer, _, _):
            if let data = NSMutableData(capacity: ExtendedLength.Short - 1) {
                var networkStatus = statusCode.bigEndian
                withUnsafePointer(&networkStatus) { (statusBytes) -> Void in
                    data.appendBytes(UnsafePointer<Void>(statusBytes), length: sizeof(UInt16))
                }
                if let message = message?.cStringUsingEncoding(NSUTF8StringEncoding) {
                    if message.count + sizeof(UInt16) < ExtendedLength.Short - 1 {
                        message.withUnsafeBufferPointer { (message) -> Void in
                            data.appendBytes(message.baseAddress, length: message.count)
                        }
                    }
                }

                if let header = serializer.beginFrameWithOpCode(.ConnectionClose, isFinal: true, length: UInt64(data.length)) {
                    outputStream.writeData(header)
                    outputStream.writeData(originalRequest == nil ? data : serializer.maskedData(data))
                }
                state = .ClosingWithStatusCode(statusCode)
            }
            
        default:
            break
        }
    }
}

extension WebSocket {

    func initializeInputStream(inputStream: NSInputStream, outputStream: NSOutputStream) {
        let securityLevel = scheme!.isSecure ? NSStreamSocketSecurityLevelTLSv1 : NSStreamSocketSecurityLevelNone
        inputStream.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)
        outputStream.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)

        let runLoop = self.runLoop ?? NSRunLoop.currentRunLoop()
        inputStream.scheduleInRunLoop(runLoop, forMode: runLoopMode)
        outputStream.scheduleInRunLoop(runLoop, forMode: runLoopMode)

        self.inputStream = DataInputStream(inputStream: inputStream)
        self.outputStream = DataOutputStream(outputStream: outputStream)

        outputStream.open()
        inputStream.open()
    }

    private func handleClientHandshake(result: ClientHandshake.Result) {
        switch result {
        case .Incomplete:
            break

        case .Invalid:
            state = .ClosingWithError(NSError(domain: ErrorDomain, code: Errors.InvalidHandshake.rawValue, userInfo: nil))

        case .Response(let response, let data):
            let tokenizer = FrameTokenizer(masked: false)
            tokenizer.delegate = self
            state = .Open(tokenizer: tokenizer, serializer: FrameSerializer(masked: true), opCode: nil, isFinal: nil)
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
            state = .ClosingWithError(NSError(domain: ErrorDomain, code: Errors.InvalidHandshake.rawValue, userInfo: nil))

        case .Request(let request, let data):
            if delegate?.webSocket?(self, shouldAcceptConnectionWithRequest: request) ?? true {
                _currentRequest = request
                if let responseData = handshake.responseData {
                    outputStream.writeData(responseData)
                    let tokenizer = FrameTokenizer(masked: true)
                    tokenizer.delegate = self
                    state = .Open(tokenizer: tokenizer, serializer: FrameSerializer(masked: false), opCode: nil, isFinal: nil)
                    if data != nil {
                        handleTokenizerError(tokenizer.readData(data!))
                    }
                }
            }
            switch state {
            case .ServerConnecting:
                state = .ClosingWithError(NSError(domain: ErrorDomain, code: Errors.InvalidHandshake.rawValue, userInfo: nil))
            default:
                break
            }
        }
    }

    private func handleTokenizerError(error: NSError?) {
        if error != nil {
            state = .ClosingWithError(error!)
        }
    }

}

extension WebSocket: DataInputStreamDelegate {

    func dataInputStream(dataInputStream: DataInputStream, didReadData data: NSData) {
        switch state {
        case .ClientConnecting(let handshake):
            handleClientHandshake(handshake.readData(data))
        case .ServerConnecting(let handshake):
            handleServerHandshake(handshake, result: handshake.readData(data))
        case .Open(let tokenizer, _, _, _):
            handleTokenizerError(tokenizer.readData(data))
        default:
            break
        }
    }

    func dataInputStream(dataInputStream: DataInputStream, didCloseWithError error: NSError) {
        dlog("\(__FUNCTION__): \(error) (\(state))")
        inputStream = nil
        switch state {
        case .ClosingWithError, .ClosingWithStatusCode, .Closed:
            break
        default:
            state = .ClosingWithError(error)
        }
    }

    func dataInputStreamDidReadToEnd(dataInputStream: DataInputStream) {
        dlog(__FUNCTION__)
        inputStream = nil
        if let stream = outputStream {
            stream.close()
        } else {
            state = .Closed
        }
    }

}

extension WebSocket: DataOutputStreamDelegate {

    func dataOutputStream(dataOutputStream: DataOutputStream, didCloseWithError error: NSError) {
        dlog("\(__FUNCTION__): \(error)")
        outputStream = nil
        switch state {
        case .Closed:
            break
        case .ClosingWithError, .ClosingWithStatusCode:
            state = .Closed
        default:
            state = .ClosingWithError(error)
        }
    }

    func dataOutputStreamDidClose(dataOutputStream: DataOutputStream) {
        dlog(__FUNCTION__)
        outputStream = nil
        state = .Closed
    }
}

extension WebSocket: FrameTokenizerDelegate {

    func frameTokenizer(frameTokenizer: FrameTokenizer, didBeginFrameWithOpCode opCode: OpCode, isFinal: Bool, reservedBits: (Bit, Bit, Bit)) {
//        dlog("Got frame with opCode: %@", "\(opCode.rawValue)")
        var isBinary = false
        switch state {
        case .Open(let tokenizer, let serializer, _, _):
            switch opCode {
            case .Binary:
                delegate?.webSocketWillBeginBinaryData(self)
            case .Text:
                delegate?.webSocketWillBeginTextData(self)
            case .Continuation:
                break
            case .Ping where isFinal:
                delegate?.webSocketDidPing?(self)
            case .Pong where isFinal:
                delegate?.webSocketDidPong?(self)
            default:
                closeWithStatusCode(NormalStatusCode, message: nil)
                return
            }
            state = .Open(tokenizer: tokenizer, serializer: serializer, opCode: opCode, isFinal: isFinal)
        default:
            dlog("Invalid state for opCode")
        }
    }

    func frameTokenizer(frameTokenizer: FrameTokenizer, didReadFrameLength frameLength: UInt64) {
//        dlog("%@ %@", __FUNCTION__, "\(frameLength)")
        switch state {
        case .Open(_, let serializer, .Some(.Ping), _):
            if let data = serializer.beginFrameWithOpCode(.Pong, isFinal: true, length: frameLength) {
                outputStream.writeData(data)
            } else {
                closeWithStatusCode(ProtocolErrorStatusCode, message: nil)
            }
        default:
            break
        }
    }

    func frameTokenizer(frameTokenizer: FrameTokenizer, didReadData data: NSData) {
//        dlog("%@ %@", __FUNCTION__, data)
        switch state {
        case .Open(_, _, .Some(let opCode), _):
            switch opCode {
            case .Text, .Binary, .Continuation:
                delegate?.webSocket(self, didReadData: data)
            case .Ping:
                outputStream.writeData(data)
            default:
                break
            }
        default:
            break
        }
    }

    func frameTokenizerDidEndFrame(frameTokenizer: FrameTokenizer) {
//        dlog("%@", __FUNCTION__)
        switch state {
        case .Open(let tokenizer, let serializer, .Some(let opCode), .Some(let isFinal)):
            switch opCode {
            case .Binary, .Text, .Continuation where isFinal == true:
                delegate?.webSocketDidFinishData(self)
            default:
                break
            }
            state = .Open(tokenizer: tokenizer, serializer: serializer, opCode: nil, isFinal: nil)
        default:
            break
        }
    }

}
