// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public enum Scoring {
    public static func recycleScore(cells: Int, groups: Int, level: Int, chain: Int) -> Int {
        let base = cells * 35 * max(1, level)
        let groupBonus = groups * 80
        let chainMul = 1 + max(0, chain - 1)
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
