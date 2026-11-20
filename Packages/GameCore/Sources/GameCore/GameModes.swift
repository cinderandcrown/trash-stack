// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

public enum PlayMode: String, Sendable, CaseIterable, Codable {
    case shift
    case endless
    case daily
    /// Real-time 1v1 — TRASH TALK.
    case trashTalk
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
    // TRASH TALK / competition
    public static let firstTrashTalkWin = "ts_tt_first_win"
    public static let trashTalkWinStreak3 = "ts_tt_streak_3"
    public static let trashTalkWinStreak5 = "ts_tt_streak_5"
    public static let fourRowClear = "ts_four_clear"
    public static let sendTenJunk = "ts_junk_10"
    public static let sendFiftyJunk = "ts_junk_50"
    public static let weeklyTop10 = "ts_weekly_top10"
    public static let weeklyChampion = "ts_weekly_champ"
    public static let allTime10k = "ts_score_10k"
    public static let allTime50k = "ts_score_50k"
    public static let beatFriendScore = "ts_beat_friend"
    public static let rematchWin = "ts_tt_rematch_win"
    public static let surviveNearMiss = "ts_near_miss"
    /// Shared with Neon City Bandit via Game Center group (same identifier in both apps).
    public static let banditOfBothWorlds = "cc_bandit_of_both_worlds"

    public static var allConfigured: [(id: String, name: String, points: Int)] {
        [
            (firstRecycle, "First Recycle", 5),
            (chainFive, "Chain Reaction", 10),
            (pressSlam, "Press Operator", 5),
            (dailyClear, "Daily Dump Cleared", 5),
            (streakSeven, "Week on the Job", 15),
            (snatchUsed, "Sticky Fingers", 5),
            (firstTrashTalkWin, "First Trash Talk Win", 10),
            (trashTalkWinStreak3, "Trash Talk Streak ×3", 15),
            (trashTalkWinStreak5, "Trash Talk Streak ×5", 25),
            (fourRowClear, "Quad Clear", 10),
            (sendTenJunk, "Junk Courier", 10),
            (sendFiftyJunk, "Junk Tycoon", 20),
            (weeklyTop10, "Weekly Top 10", 15),
            (weeklyChampion, "Weekly Champion", 50),
            (allTime10k, "Night Shift 10K", 10),
            (allTime50k, "Night Shift 50K", 25),
            (beatFriendScore, "Beat a Friend", 10),
            (rematchWin, "Rematch Revenge", 10),
            (surviveNearMiss, "Lip of the Bin", 5),
            (banditOfBothWorlds, "Bandit of Both Worlds", 50),
        ]
    }
}
