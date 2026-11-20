// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Shared crate loot table — UI odds and the roll must read from this only.
public enum CrateLoot {
    public static let scrapMin = 40
    public static let scrapMax = 80
    /// Inclusive gem outcomes, each equally likely.
    public static let gemOutcomes: [Int] = [0, 1, 2]

    public static var scrapChancePercent: Int { 100 }

    public static var gemOutcomeChancePercent: Double {
        100.0 / Double(gemOutcomes.count)
    }

    /// Chance that gems > 0 (for display + tests).
    public static var bonusGemsChancePercent: Double {
        let positive = gemOutcomes.filter { $0 > 0 }.count
        return 100.0 * Double(positive) / Double(gemOutcomes.count)
    }

    /// Human-readable odds line shown on the crate screen.
    public static var oddsDisplayLine: String {
        let gemBits = gemOutcomes.map { g in
            // One decimal so 33.3×3 reads as 100%.
            let pct = String(format: "%.1f", gemOutcomeChancePercent)
            return "\(g) (\(pct)%)"
        }.joined(separator: " / ")
        return "Odds · Scrap \(scrapMin)-\(scrapMax) (\(scrapChancePercent)%) · Gems: \(gemBits)"
    }

    public static func roll(
        scrapRandom: (ClosedRange<Int>) -> Int = { Int.random(in: $0) },
        gemIndexRandom: (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
    ) -> (scrap: Int, gems: Int) {
        let scrapSpan = scrapMax - scrapMin
        let scrap = scrapMin + scrapRandom(0...scrapSpan)
        let idx = gemIndexRandom(0...(gemOutcomes.count - 1))
        let gems = gemOutcomes[idx]
        return (scrap, gems)
    }
}
