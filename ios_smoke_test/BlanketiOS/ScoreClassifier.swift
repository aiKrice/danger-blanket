//
//  ScoreClassifier.swift
//  BlanketiOS
//
//  Coverage fixture: ScoreClassifierTests only ever calls `label` with
//  passing scores, so the ternary's "fail" branch text never executes even
//  though the line it sits on does - xccov records that as a sub-line span
//  (yellow highlight over an otherwise-green/covered line), not a whole
//  extra uncovered line.
//

import Foundation

enum ScoreClassifier {
    static func label(for score: Int) -> String {
        return score >= 50 ? "pass" : "fail"
    }
}
