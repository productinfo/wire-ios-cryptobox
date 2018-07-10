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

class CacheTests: XCTestCase {
    func testThatItStoresAndReadsValue() {
        // GIVEN
        let cache = CachingEncryptor.Cache<String, String>(maxCost: 1000, maxElements: 10)
        // WHEN
        cache.set(value: "Hello", for: "word", cost: 1)
        // THEN
        XCTAssertEqual(cache.value(for: "word"), "Hello")
    }
    
    func testThatItPurgesWhenTooManyElements() {
        // GIVEN
        let cache = CachingEncryptor.Cache<String, String>(maxCost: 1000, maxElements: 10)
        // WHEN
        (0..<11).forEach {
            cache.set(value: "Hello \($0)", for: "word \($0)", cost: 1)
        }
        
        // THEN
        XCTAssertEqual(cache.value(for: "word 10"), "Hello 10")
        XCTAssertEqual(cache.value(for: "word 1"), "Hello 1")
        XCTAssertEqual(cache.value(for: "word 0"), nil)
    }
    
    func testThatItPurgesWhenCostIsTooHigh() {
        // GIVEN
        let cache = CachingEncryptor.Cache<String, String>(maxCost: 10, maxElements: 10)
        // WHEN
        cache.set(value: "Hello 0", for: "word 0", cost: 2)
        cache.set(value: "Hello 1", for: "word 1", cost: 2)
        cache.set(value: "Hello 2", for: "word 2", cost: 2)
        cache.set(value: "Hello 3", for: "word 3", cost: 5)
        
        // THEN
        XCTAssertEqual(cache.value(for: "word 3"), "Hello 3")
        XCTAssertEqual(cache.value(for: "word 2"), "Hello 2")
        XCTAssertEqual(cache.value(for: "word 1"), "Hello 1")
        XCTAssertEqual(cache.value(for: "word 0"), nil)
    }
    
    func testThatItPurgesWhenCostIsTooHigh_MultipleDeletes() {
        // GIVEN
        let cache = CachingEncryptor.Cache<String, String>(maxCost: 10, maxElements: 10)
        // WHEN
        cache.set(value: "Hello 0", for: "word 0", cost: 1)
        cache.set(value: "Hello 1", for: "word 1", cost: 1)
        cache.set(value: "Hello 2", for: "word 2", cost: 3)
        cache.set(value: "Hello 3", for: "word 3", cost: 5)
        cache.set(value: "Hello 4", for: "word 4", cost: 5)
        
        // THEN
        XCTAssertEqual(cache.value(for: "word 4"), "Hello 4")
        XCTAssertEqual(cache.value(for: "word 3"), "Hello 3")
        XCTAssertEqual(cache.value(for: "word 2"), nil)
        XCTAssertEqual(cache.value(for: "word 1"), nil)
        XCTAssertEqual(cache.value(for: "word 0"), nil)
    }
}
