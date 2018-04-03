//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation
import Sodium

public final class ChaCha20Encryption {
    
    private static let bufferSize = 1024
    
    public enum EncryptionError : Error {
        /// Couldn't read  corrupt message header
        case malformedHeader
        /// Decryption failed to incorrect key, malformed message
        case decryptionFailed
        /// Failure reading input stream
        case readError(Error?)
        /// Failure writing to output stream
        case writeError(Error?)
    }
    
    /// ChaCha20 Key
    public struct Key {
        let buffer: Array<UInt8>
        
        public init() {
            var buffer = Array<UInt8>(repeating: 0, count: Int(crypto_secretstream_xchacha20poly1305_KEYBYTES))
            crypto_secretstream_xchacha20poly1305_keygen(&buffer)
            self.buffer = buffer
        }
    }
    
    /// Encrypts an input stream using xChaCha20
    /// - input: plaintext input stream
    /// - output: decrypted output stream
    ///
    /// - Throws: Stream errors.
    /// - Returns: number of encrypted bytes written to the output stream
    @discardableResult
    public static func encrypt(input: InputStream, output: OutputStream, key: Key) throws -> Int {
        input.open()
        output.open()
        
        defer {
            input.close()
            output.close()
        }

        var header = Array<UInt8>(repeating: 0, count: Int(crypto_secretstream_xchacha20poly1305_HEADERBYTES))
        var state = crypto_secretstream_xchacha20poly1305_state()
        
        crypto_secretstream_xchacha20poly1305_init_push(&state, &header, key.buffer);
        
        var messageBuffer = Array<UInt8>(repeating: 0, count: bufferSize)
        let cipherBufferSize = bufferSize + Int(crypto_secretstream_xchacha20poly1305_ABYTES)
        var cipherBuffer = Array<UInt8>(repeating: 0, count: cipherBufferSize)
        
        var totalBytesWritten = 0
        var bytesWritten = -1
        var bytesRead = -1
        
        bytesWritten = output.write(header, maxLength: Int(crypto_secretstream_xchacha20poly1305_HEADERBYTES))
        totalBytesWritten += bytesWritten
        
        guard bytesWritten > 0 else {
            throw EncryptionError.writeError(output.streamError)
        }
        
        repeat {
            bytesRead = input.read(&messageBuffer, maxLength: bufferSize)
            
            guard bytesRead > 0 else { break }
            
            let messageLength: UInt64 = UInt64(bytesRead)
            var cipherLength: UInt64 = 0
            let tag: UInt8 = input.hasBytesAvailable ? 0 : UInt8(crypto_secretstream_xchacha20poly1305_TAG_FINAL)
            
            crypto_secretstream_xchacha20poly1305_push(&state, &cipherBuffer, &cipherLength, messageBuffer, messageLength, nil, 0, tag)
            
            bytesWritten = output.write(cipherBuffer, maxLength: Int(cipherLength))
            totalBytesWritten += bytesWritten
        } while bytesRead > 0 && bytesWritten > 0
        
        if bytesRead < 0 {
            throw EncryptionError.readError(input.streamError)
        }
        
        if bytesWritten < 0 {
            throw EncryptionError.writeError(output.streamError)
        }
        
        return totalBytesWritten
    }
    
    /// Decrypts an input stream using xChaCha20
    /// - input: encrypted input stream
    /// - output: plaintext output stream
    ///
    /// - Throws: Stream errors and `malformedHeader` or `decryptionFailed` if decryption fails.
    /// - Returns: number of decrypted bytes written to the output stream.
    @discardableResult
    public static func decrypt(input: InputStream, output: OutputStream, key: Key) throws -> Int {
        input.open()
        output.open()
        
        defer {
            input.close()
            output.close()
        }
        
        var totalBytesWritten = 0
        var bytesWritten = -1
        var bytesRead = -1
        
        var state = crypto_secretstream_xchacha20poly1305_state()
        var header = Array<UInt8>(repeating: 0, count: Int(crypto_secretstream_xchacha20poly1305_HEADERBYTES))
        
        guard input.read(&header, maxLength: Int(crypto_secretstream_xchacha20poly1305_HEADERBYTES)) > 0  else {
            throw EncryptionError.readError(input.streamError)
        }

        guard crypto_secretstream_xchacha20poly1305_init_pull(&state, header, key.buffer) == 0 else {
            throw EncryptionError.malformedHeader
        }
        
        var messageBuffer = Array<UInt8>(repeating: 0, count: bufferSize)
        let cipherBufferSize = bufferSize + Int(crypto_secretstream_xchacha20poly1305_ABYTES)
        var cipherBuffer = Array<UInt8>(repeating: 0, count: cipherBufferSize)
        var tag: UInt8 = 0
        
        repeat {
            bytesRead = input.read(&cipherBuffer, maxLength: cipherBufferSize)
            
            guard bytesRead > 0 else { continue }
            
            var messageLength: UInt64 = 0
            let cipherLength: UInt64 = UInt64(bytesRead)
            
            guard crypto_secretstream_xchacha20poly1305_pull(&state, &messageBuffer, &messageLength, &tag, cipherBuffer, cipherLength, nil, 0) == 0 else {
                throw EncryptionError.decryptionFailed
            }
            
            bytesWritten = output.write(messageBuffer, maxLength: Int(messageLength))
            totalBytesWritten += bytesWritten
        } while bytesRead > 0 && bytesWritten > 0
        
        guard tag == crypto_secretstream_xchacha20poly1305_TAG_FINAL else {
            throw EncryptionError.decryptionFailed
        }
        
        if bytesRead < 0 {
            throw EncryptionError.readError(input.streamError)
        }
        
        if bytesWritten < 0 {
            throw EncryptionError.writeError(output.streamError)
        }
        
        return totalBytesWritten
    }
    
}