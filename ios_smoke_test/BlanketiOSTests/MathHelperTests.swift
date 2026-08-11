//
//  MathHelperTests.swift
//  BlanketiOSTests
//

import Testing
@testable import BlanketiOS

struct MathHelperTests {
    @Test func add() async throws {
        #expect(MathHelper.add(2, 3) == 5)
    }

    @Test func multiply() async throws {
        #expect(MathHelper.multiply(2, 3) == 6)
    }

    @Test func isEven() async throws {
        #expect(MathHelper.isEven(4) == true)
        #expect(MathHelper.isEven(3) == false)
    }
}
