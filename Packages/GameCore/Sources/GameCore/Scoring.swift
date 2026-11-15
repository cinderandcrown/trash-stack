// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public enum Scoring {
    public static let lineScores = [0, 100, 300, 500, 800]

    public static func crushScore(lines: Int, level: Int, combo: Int, backToBack: Bool) -> Int {
        let base = (lineScores[min(4, lines)] ) * max(1, level)
        var gained = base + lines * 80 * level
        if lines >= 3 && backToBack { gained = Int(Double(gained) * 1.5) }
        if combo > 0 { gained += 50 * combo * level }
        return gained
    }

    public static func scrapForClear(lines: Int, combo: Int, leveled: Bool) -> Int {
        let table = [0, 2, 4, 8, 14]
        var sh = table[min(4, lines)] + max(0, combo - 1)
        if lines >= 3 { sh += 5 }
        if leveled { sh += 10 }
        return sh
    }

    public static func scrapForRecycle(groups: Int, cells: Int) -> Int {
        2 + groups * 2 + max(0, cells / 6)
    }
}
