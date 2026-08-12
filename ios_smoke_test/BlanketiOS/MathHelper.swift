//
//  MathHelper.swift
//  BlanketiOS
//
//  Coverage fixture: every branch below is exercised by MathHelperTests,
//  so this file should sit at (or near) 100% line coverage.
//

import Foundation

enum MathHelper {
    static func add(_ a: Int, _ b: Int) -> Int {
        return a + b
    }

    static func multiply(_ a: Int, _ b: Int) -> Int {
        return a * b
    }

    static func isEven(_ n: Int) -> Bool {
        return n % 2 == 0
    }
}
