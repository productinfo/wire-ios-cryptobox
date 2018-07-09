//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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


import XCTest
@testable import WireCryptobox

let someTextToEncrypt = "ENCRYPT THIS!"

class EncryptionContextCachingTests: XCTestCase {
    func testThatItDoesNotCachePerDefault() {
        // GIVEN
        let tempDir = createTempFolder()
        let mainContext = EncryptionContext(path: tempDir)
        
        let expectation = self.expectation(description: "Encryption succeeded")
        
        // WHEN
        mainContext.perform { sessionContext in
            try! sessionContext.createClientSession(hardcodedClientId, base64PreKeyString: hardcodedPrekey)
            
            let encryptedDataNonCachedFirst  = try! sessionContext.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: hardcodedClientId)
            let encryptedDataNonCachedSecond = try! sessionContext.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: hardcodedClientId)
            
            XCTAssertNotEqual(encryptedDataNonCachedFirst, encryptedDataNonCachedSecond)
            
            expectation.fulfill()
        }
        
        // THEN
        self.waitForExpectations(timeout: 0) { _ in }
    }
    
    func testThatItCachesWhenRequested() {
        // GIVEN
        let tempDir = createTempFolder()
        let mainContext = EncryptionContext(path: tempDir)
        
        let expectation = self.expectation(description: "Encryption succeeded")
        
        // WHEN
        mainContext.perform { sessionContext in
            try! sessionContext.createClientSession(hardcodedClientId, base64PreKeyString: hardcodedPrekey)
            
            let encryptedDataFirst  = try! sessionContext.cachingEncryptor.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: hardcodedClientId)
            let encryptedDataSecond = try! sessionContext.cachingEncryptor.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: hardcodedClientId)
            
            XCTAssertEqual(encryptedDataFirst, encryptedDataSecond)
            
            expectation.fulfill()
        }
        
        // THEN
        self.waitForExpectations(timeout: 0) { _ in }
    }
    
    func testThatCacheKeyDependsOnData() {
        // GIVEN
        let tempDir = createTempFolder()
        let mainContext = EncryptionContext(path: tempDir)
        
        let expectation = self.expectation(description: "Encryption succeeded")
        
        // WHEN
        mainContext.perform { sessionContext in
            try! sessionContext.createClientSession(hardcodedClientId, base64PreKeyString: hardcodedPrekey)
            
            let encryptedDataFirst  = try! sessionContext.cachingEncryptor.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: hardcodedClientId)
            let encryptedDataSecond = try! sessionContext.cachingEncryptor.encrypt(someTextToEncrypt.appending(someTextToEncrypt).data(using: String.Encoding.utf8)!, for: hardcodedClientId)
            
            XCTAssertNotEqual(encryptedDataFirst, encryptedDataSecond)
            
            expectation.fulfill()
        }
        
        // THEN
        self.waitForExpectations(timeout: 0) { _ in }
    }
    
    func testThatCacheKeyDependsOnSessionId() throws {
        // GIVEN
        class DebugEncryptor: Encryptor {
            var index: Int = 0
            func encrypt(_ plainText: Data, for recipientIdentifier: EncryptionSessionIdentifier) throws -> Data {
                var result = plainText
                result.append(recipientIdentifier.rawValue.data(using: .utf8)!)
                result.append("\(index)".data(using: .utf8)!)
                return result
            }
        }
        let debugEncryptor = DebugEncryptor()
        let cachingEncryptor = CachingEncryptor(encryptor: debugEncryptor)
        
        let otherSessionIdentifier = EncryptionSessionIdentifier(rawValue: "1e9b4e187a9eb716")
        // WHEN
        
        let data1 = try cachingEncryptor.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: hardcodedClientId)
        let data2 = try cachingEncryptor.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: otherSessionIdentifier)
        // THEN
        XCTAssertNotEqual(data1, data2)
    }
    
    func testThatItCachesWhenRequested_SimpleSetup() throws {
        // GIVEN
        class DebugEncryptor: Encryptor {
            var index: Int = 0
            func encrypt(_ plainText: Data, for recipientIdentifier: EncryptionSessionIdentifier) throws -> Data {
                var result = plainText
                result.append(recipientIdentifier.rawValue.data(using: .utf8)!)
                result.append("\(index)".data(using: .utf8)!)
                return result
            }
        }
        let debugEncryptor = DebugEncryptor()
        let cachingEncryptor = CachingEncryptor(encryptor: debugEncryptor)
        // WHEN
        
        let data1 = try cachingEncryptor.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: hardcodedClientId)
        let data2 = try cachingEncryptor.encrypt(someTextToEncrypt.data(using: String.Encoding.utf8)!, for: hardcodedClientId)
        // THEN
        XCTAssertEqual(data1, data2)
    }
}
