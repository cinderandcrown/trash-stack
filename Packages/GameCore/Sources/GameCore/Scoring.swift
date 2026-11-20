// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public enum Scoring {
    /// Calm pace — a solid minute of play, not a 40s rocket to L8.
    public static func recycleScore(cells: Int, groups: Int, level: Int, chain: Int) -> Int {
        let base = cells * 18 * max(1, level)
        let groupBonus = groups * 40
        // Chains escalate gently and hard-cap so score stays readable.
        let chainMul: Int
        switch max(1, chain) {
        case 1: chainMul = 1
        case 2: chainMul = 2
        default: chainMul = 3 // cap
        }
        return (base + groupBonus) * chainMul
    }

    public static func scrapForRecycle(groups: Int, cells: Int) -> Int {
        max(1, cells / 2 + groups)
    }

    public static func pressScore(cells: Int, level: Int) -> Int {
        cells * 12 * max(1, level) + 60
    }

    public static func scrapForPress(cells: Int) -> Int {
        max(2, cells)
    }

    /// Lines needed per level — ~60–90s for a decent player.
    public static let linesPerLevel = 14
}
