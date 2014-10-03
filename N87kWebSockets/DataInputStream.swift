//
//  DataInputStream.swift
//  N87kWebSockets
//
//  Created by jacob berkman on 9/21/14.
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

protocol DataInputStreamDelegate: NSObjectProtocol {
    func dataInputStream(dataInputStream: DataInputStream, didReadData data: NSData)
    func dataInputStream(dataInputStream: DataInputStream, didCloseWithError error: NSError)
    func dataInputStreamDidReadToEnd(dataInputStream: DataInputStream)
}

class DataInputStream: NSObject {

    weak var delegate: DataInputStreamDelegate?

    private let inputStream: NSInputStream

    init(inputStream: NSInputStream) {
        self.inputStream = inputStream
        super.init()
        self.inputStream.delegate = self
    }

    deinit {
        inputStream.delegate = nil
    }
    
}

extension DataInputStream {

    private func readData() {
        let bufferSize = 8192
        let data = NSMutableData(length: bufferSize)
        let bytesRead = inputStream.read(UnsafeMutablePointer<UInt8>(data.mutableBytes), maxLength: bufferSize)
        if bytesRead < 0 {
            NSLog("Error reading from input")
            delegate?.dataInputStream(self, didCloseWithError: inputStream.streamError!)
            return
        }
        data.length = bytesRead
        delegate?.dataInputStream(self, didReadData: data)
    }

}

extension DataInputStream: NSStreamDelegate {

    func stream(stream: NSStream, handleEvent streamEvent: NSStreamEvent) {
        if streamEvent & .HasBytesAvailable == .HasBytesAvailable {
            NSLog("HasBytesAvailable: %@", stream)
            readData()
        }
        if streamEvent & .ErrorOccurred == .ErrorOccurred {
            NSLog("ErrorOccurred: %@", stream.streamError!)
            delegate?.dataInputStream(self, didCloseWithError: stream.streamError!)
        }
        if streamEvent & .EndEncountered == .EndEncountered {
            delegate?.dataInputStreamDidReadToEnd(self)
        }
    }

}
