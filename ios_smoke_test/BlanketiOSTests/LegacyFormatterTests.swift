//
//  LegacyFormatterTests.swift
//  BlanketiOSTests
//
//  Deliberately only covers formatCurrency - formatPercentage/formatDate
//  are the "below threshold" half of this coverage fixture, see
//  LegacyFormatter.swift.
//

import Testing
@testable import BlanketiOS

struct LegacyFormatterTests {
    @Test func formatCurrency() async throws {
        #expect(LegacyFormatter.formatCurrency(4.5) == "$4.50")
    }
}
