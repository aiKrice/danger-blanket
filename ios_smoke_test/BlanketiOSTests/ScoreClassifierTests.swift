//
//  ScoreClassifierTests.swift
//  BlanketiOSTests
//
//  Only ever calls `label` with a passing score - see the note in
//  ScoreClassifier.swift about why that leaves a sub-line span uncovered
//  rather than a whole extra red line.
//

import Testing
@testable import BlanketiOS

struct ScoreClassifierTests {
    @Test func labelForPassingScore() async throws {
        #expect(ScoreClassifier.label(for: 80) == "pass")
    }
}
