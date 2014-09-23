//
//  WebSocketClientHandshake.swift
//  N87kWebSockets
//
//  Created by jacob berkman on 9/22/14.
//  Copyright (c) 2014 jacob berkman. All rights reserved.
//

import CFNetwork
import Foundation
import Security

class WebSocketClientHandshake: NSObject {
    private let request: NSURLRequest
    private let responseMessage = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, Boolean(0)).takeRetainedValue()
    private var expectedAccept: String?

    private struct Const {
        static let HTTPVersion: NSString = "HTTP/1.1"
        static let GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        static let UpgradeStatusCode = 101
    }

    private struct HeaderKeys {
        static let Connection = "Connection"
        static let Host = "Host"
        static let SecWebSocketAccept = "Sec-WebSocket-Accept"
        static let SecWebSocketKey = "Sec-WebSocket-Key"
        static let SecWebSocketVersion = "Sec-WebSocket-Version"
        static let SecWebSocketExtensions = "Sec-WebSocket-Extensions"
        static let Upgrade = "Upgrade"
    }

    private struct HeaderValues {
        static let Upgrade = "upgrade"
        static let Version = "13"
        static let WebSocket = "websocket"
    }

    init(request: NSURLRequest) {
        self.request = request
        super.init()
    }

    private class func generateKey() -> String? {
        let keyLength = 16
        let data = NSMutableData(length: keyLength)
        if SecRandomCopyBytes(kSecRandomDefault, UInt(keyLength), UnsafeMutablePointer<UInt8>(data.mutableBytes)) != 0 {
            return nil
        }
        return data.base64EncodedStringWithOptions(nil)
    }

    private var scheme: Scheme? {
        return request.URL.scheme != nil ? Scheme.fromRaw(request.URL.scheme!) : nil
    }

    var requestData: NSData? {
        let key = self.dynamicType.generateKey()
        if key == nil {
            NSLog("Could not generate random key");
            // FIXME
            return nil
        }

        expectedAccept = "\(key!)\(Const.GUID)".N87k_SHA1Digest
        let port = request.URL.port != nil && request.URL.port != scheme!.defaultPort ? ":\(request.URL.port!)" : ""

        let requestMessage = CFHTTPMessageCreateRequest(kCFAllocatorDefault, request.HTTPMethod! as NSString, request.URL, Const.HTTPVersion).takeRetainedValue()
        let headers: [NSString: NSString] = [
            HeaderKeys.Host: "\(request.URL.host!)\(port)",
            HeaderKeys.Connection: HeaderValues.Upgrade,
            HeaderKeys.Upgrade: HeaderValues.WebSocket,
            HeaderKeys.SecWebSocketVersion: HeaderValues.Version,
            HeaderKeys.SecWebSocketKey: key!
        ]
        if let requestHeaders = request.allHTTPHeaderFields as? [NSString: NSString] {
            for (k, v) in requestHeaders {
                if headers[k] == nil {
                    CFHTTPMessageSetHeaderFieldValue(requestMessage, k, v)
                }
            }

        }
        for (k, v) in headers {
            CFHTTPMessageSetHeaderFieldValue(requestMessage, k, v)
        }

        return CFHTTPMessageCopySerializedMessage(requestMessage)?.takeRetainedValue()
    }

    func parseData(data: NSData, completion: (NSHTTPURLResponse?, NSData?) -> Void) {
        CFHTTPMessageAppendBytes(responseMessage, UnsafePointer<UInt8>(data.bytes), data.length)
        if CFHTTPMessageIsHeaderComplete(responseMessage) == Boolean(0) {
            return
        }

        var response: NSHTTPURLResponse?
        var responseData: NSData?
        if let HTTPVersion: NSString = CFHTTPMessageCopyVersion(responseMessage)?.takeRetainedValue() {
            let statusCode = CFHTTPMessageGetResponseStatusCode(responseMessage)
            if let headerFields: NSDictionary = CFHTTPMessageCopyAllHeaderFields(responseMessage)?.takeRetainedValue() {
                if HTTPVersion == Const.HTTPVersion && statusCode == Const.UpgradeStatusCode &&
                    headerFields[HeaderKeys.Connection]?.lowercaseString == HeaderValues.Upgrade &&
                    headerFields[HeaderKeys.Upgrade]?.lowercaseString == HeaderValues.WebSocket &&
                    headerFields[HeaderKeys.SecWebSocketAccept]?.lowercaseString == expectedAccept &&
                    headerFields[HeaderKeys.SecWebSocketExtensions] == nil {
                        response = NSHTTPURLResponse(URL: request.URL, statusCode: statusCode, HTTPVersion: HTTPVersion, headerFields: headerFields)
                        responseData = CFHTTPMessageCopyBody(responseMessage)?.takeRetainedValue()
                }
            }
        }
        completion(response, responseData)
    }
}
