// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

public enum PlayMode: String, Sendable, CaseIterable, Codable {
    case shift
    case endless
    case daily
}

public struct ShiftLevel: Sendable, Equatable, Identifiable {
    public var id: String
    public var district: String
    public var title: String
    public var starGoals: [String]
    /// Mechanics unlocked by this level index (documented for UI).
    public var unlocks: [String]

    public init(id: String, district: String, title: String, starGoals: [String], unlocks: [String] = []) {
        self.id = id
        self.district = district
        self.title = title
        self.starGoals = starGoals
        self.unlocks = unlocks
    }
}

public enum ShiftCatalog {
    public static let levels: [ShiftLevel] = [
        ShiftLevel(id: "d1-01", district: "Alley Mouth", title: "First Pickup",
                   starGoals: ["Recycle 8 metal", "Score 1,500", "Slam press once"]),
        ShiftLevel(id: "d1-02", district: "Alley Mouth", title: "Glass Run",
                   starGoals: ["Recycle 12 glass", "Chain ×2", "Finish under 40 drops"]),
        ShiftLevel(id: "d2-01", district: "Battery Yard", title: "Leaky Night",
                   starGoals: ["Survive battery hazard", "Recycle 15 metal", "3 stars clear"],
                   unlocks: ["leakingBattery"]),
        ShiftLevel(id: "d2-02", district: "Battery Yard", title: "Sticky Situation",
                   starGoals: ["Press sticky goo", "Chain ×3", "Score 4,000"],
                   unlocks: ["sticky"]),
        ShiftLevel(id: "d3-01", district: "Magnet Row", title: "Pull Shift",
                   starGoals: ["Use Snatch", "Recycle 20 plastic", "Order complete"],
                   unlocks: ["magnetAssist"]),
        ShiftLevel(id: "d4-01", district: "Conveyor Docks", title: "Belt Blues",
                   starGoals: ["Clear district orders", "Chain ×4", "No overflow"],
                   unlocks: ["conveyor"]),
    ]
}

public enum DailyDumpster {
    /// UTC calendar day seed — same for everyone that day.
    public static func seed(for date: Date = Date(), calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()) -> UInt64 {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = UInt64(comps.year ?? 2026)
        let m = UInt64(comps.month ?? 1)
        let d = UInt64(comps.day ?? 1)
        return y * 10_000 + m * 100 + d
    }

    public static func dayKey(for date: Date = Date()) -> String {
        let s = seed(for: date)
        return String(s)
    }

    /// Wordle-style share card from a finished board snapshot.
    public static func shareCard(
        dayKey: String,
        score: Int,
        stars: Int,
        materialGrid: [[Material?]]
    ) -> String {
        let header = "Trash Stack Daily Dumpster \(dayKey)"
        let scoreLine = "Score \(score) · \(String(repeating: "★", count: max(0, min(3, stars))))\(String(repeating: "☆", count: max(0, 3 - stars)))"
        let rows = materialGrid.suffix(6).map { row -> String in
            row.map { cell -> String in
                switch cell {
                case .metal?: return "🪙"
                case .plastic?: return "🧴"
                case .glass?: return "🫙"
                case .paper?: return "📦"
                case nil: return "⬛"
                }
            }.joined()
        }
        return ([header, scoreLine] + rows + ["#TrashStack"]).joined(separator: "\n")
    }
}

public enum StreakRewards {
    /// Escalating scrap for streak day N (1-based).
    public static func scrap(forDay day: Int) -> Int {
        min(200, 10 + day * 8)
    }

    public static func gems(forDay day: Int) -> Int {
        day > 0 && day % 7 == 0 ? 5 : (day >= 3 ? 1 : 0)
    }
}

public enum AchievementID {
    public static let firstRecycle = "ts_first_recycle"
    public static let chainFive = "ts_chain_5"
    public static let pressSlam = "ts_press_slam"
    public static let dailyClear = "ts_daily_clear"
    public static let streakSeven = "ts_streak_7"
    public static let snatchUsed = "ts_snatch"
}
