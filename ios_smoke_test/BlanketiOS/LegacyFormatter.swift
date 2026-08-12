//
//  LegacyFormatter.swift
//  BlanketiOS
//
//  Coverage fixture: only formatCurrency is exercised by
//  LegacyFormatterTests - formatPercentage/formatDate are left untested on
//  purpose, so this file sits well below any reasonable file threshold.
//

import Foundation

enum LegacyFormatter {
    static func formatCurrency(_ amount: Double) -> String {
        return String(format: "$%.2f", amount)
    }

    static func formatPercentage(_ value: Double) -> String {
        let percentage = value * 100
        return String(format: "%.1f%%", percentage)
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
