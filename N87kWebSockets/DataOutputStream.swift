//
//  DataOutputStream.swift
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

protocol DataOutputStreamDelegate: NSObjectProtocol {
    func dataOutputStream(dataOutputStream: DataOutputStream, didCloseWithError error: NSError)
    func dataOutputStreamDidClose(dataOutputStream: DataOutputStream)
}

class DataOutputStream: NSObject {

    weak var delegate: DataOutputStreamDelegate?

    private let outputStream: NSOutputStream
    private var queue = [NSData]()
    private var offset = 0
    private var isClosing = false

    init(outputStream: NSOutputStream) {
        self.outputStream = outputStream
        super.init()
        outputStream.delegate = self
    }

    deinit {
        outputStream.delegate = nil
    }

    func writeData(data: NSData) {
        queue.append(data)
        if queue.count == 1 && outputStream.hasSpaceAvailable {
            writeData()
        }
    }
    
    func close() {
        isClosing = true
        if queue.isEmpty {
            outputStream.close()
            delegate?.dataOutputStreamDidClose(self)
        }
    }
}

extension DataOutputStream {

    private func writeData() {
        if !outputStream.hasSpaceAvailable {
            return
        }
        if let data = queue.first {
            let bytes = UnsafePointer<UInt8>(data.bytes.advancedBy(offset))
            let length = data.length - offset
            let bytesWritten = outputStream.write(bytes, maxLength: length)
            NSLog("Wrote %@ bytes.", "\(bytesWritten)")
            if bytesWritten == length {
                queue.removeAtIndex(0)
                offset = 0
            } else if bytesWritten > 0 {
                offset += bytesWritten
            } else {
                NSLog("Error writing bytes: %@", outputStream.streamError!)
                delegate?.dataOutputStream(self, didCloseWithError: outputStream.streamError!)
            }
        } else if isClosing {
            outputStream.close()
            delegate?.dataOutputStreamDidClose(self)
        } else {
            NSLog("No data to write...")
        }
    }

}

extension DataOutputStream: NSStreamDelegate {

    func stream(stream: NSStream, handleEvent streamEvent: NSStreamEvent) {
        if streamEvent & .HasSpaceAvailable == .HasSpaceAvailable {
            NSLog("HasSpaceAvailable: %@", stream)
            writeData()
        }
        if streamEvent & .ErrorOccurred == .ErrorOccurred {
            NSLog("ErrorOccurred: %@", stream.streamError!)
            delegate?.dataOutputStream(self, didCloseWithError: stream.streamError!)
        }
    }

}
