// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public enum Scoring {
    public static func recycleScore(cells: Int, groups: Int, level: Int, chain: Int) -> Int {
        let base = cells * 40 * max(1, level)
        let groupBonus = groups * 100
        // Chains escalate hard: ×1, ×2, ×3, ×5, ×7…
        let chainMul: Int
        switch max(1, chain) {
        case 1: chainMul = 1
        case 2: chainMul = 2
        case 3: chainMul = 3
        case 4: chainMul = 5
        default: chainMul = 5 + (chain - 4) * 2
        }
        return (base + groupBonus) * chainMul
    }

    public static func scrapForRecycle(groups: Int, cells: Int) -> Int {
        max(1, cells / 2 + groups)
    }

    public static func pressScore(cells: Int, level: Int) -> Int {
        cells * 25 * max(1, level) + 120
    }

    public static func scrapForPress(cells: Int) -> Int {
        max(2, cells)
    }
}
