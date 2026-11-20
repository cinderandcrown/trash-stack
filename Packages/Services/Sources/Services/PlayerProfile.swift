// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
#if canImport(Combine)
import Combine
#endif

public enum PlayModePreference: String, Sendable, CaseIterable {
    case shift, endless, daily, trashTalk
}

@MainActor
public final class PlayerProfile: ObservableObject {
    public static let shared = PlayerProfile()

    @Published public var scrap: Int = 80
    @Published public var gems: Int = 20
    @Published public var highScore: Int = 0
    @Published public var endlessHighScore: Int = 0
    @Published public var playerLevel: Int = 1
    @Published public var xp: Int = 0
    @Published public var dailyStreak: Int = 0
    @Published public var lastStreakDayKey: String = ""
    @Published public var streakSavers: Int = 1
    @Published public var streakSaverWeekKey: String = ""
    @Published public var firstWin: Bool = false
    /// Cold-launch sessions completed (incremented once per process start).
    @Published public var sessionCount: Int = 0
    @Published public var notifAsked: Bool = false
    @Published public var adsRemoved: Bool = false
    @Published public var premiumPass: Bool = false
    @Published public var battlePassXP: Int = 0
    @Published public var tutorialDone: Bool = false
    /// Default ON — gesture-only was the #1 reason TestFlight builds felt unplayable.
    @Published public var classicButtons: Bool = true
    @Published public var shiftProgress: Int = 0
    @Published public var lastDailyKey: String = ""
    @Published public var lastDailyScore: Int = 0
    @Published public var cratesReady: Int = 0
    @Published public var nextCrateAt: TimeInterval = 0
    @Published public var sessionOfferShown: Bool = false
    @Published public var baseLevels: [String: Int] = [
        "recycler": 1, "compactor": 1, "neonSign": 1, "stashVault": 1,
    ]
    @Published public var baseReadyAt: [String: TimeInterval] = [:]
    @Published public var shotMode: String? = nil
    @Published public var preferredMode: PlayModePreference = .endless

    private let defaults = UserDefaults.standard

    public init() {
        load()
        refreshCrateClock()
        refreshStreakSaverWeek()
        if let arg = Self.shotArgument() {
            shotMode = arg
        } else if let shot = defaults.string(forKey: "trashStack.shot"), !shot.isEmpty {
            shotMode = shot
            defaults.removeObject(forKey: "trashStack.shot")
        }
    }

    nonisolated public static func shotArgument() -> String? {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-trashStackShot"), idx + 1 < args.count {
            let v = args[idx + 1]
            return v.isEmpty ? nil : v
        }
        return nil
    }

    nonisolated public static func utcDayKey(for date: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 2026
        let m = c.month ?? 1
        let d = c.day ?? 1
        return String(format: "%04d%02d%02d", y, m, d)
    }

    public func load() {
        scrap = defaults.object(forKey: "scrap") as? Int ?? 80
        gems = defaults.object(forKey: "gems") as? Int ?? 20
        highScore = defaults.integer(forKey: "highScore")
        endlessHighScore = defaults.integer(forKey: "endlessHighScore")
        playerLevel = max(1, defaults.integer(forKey: "playerLevel"))
        xp = defaults.integer(forKey: "xp")
        dailyStreak = defaults.integer(forKey: "dailyStreak")
        lastStreakDayKey = defaults.string(forKey: "lastStreakDayKey") ?? ""
        streakSavers = defaults.object(forKey: "streakSavers") as? Int ?? 1
        streakSaverWeekKey = defaults.string(forKey: "streakSaverWeekKey") ?? ""
        firstWin = defaults.bool(forKey: "firstWin")
        sessionCount = defaults.integer(forKey: "sessionCount")
        notifAsked = defaults.bool(forKey: "notifAsked")
        adsRemoved = defaults.bool(forKey: "adsRemoved")
        premiumPass = defaults.bool(forKey: "premiumPass")
        battlePassXP = defaults.integer(forKey: "battlePassXP")
        tutorialDone = defaults.bool(forKey: "tutorialDone")
        // Unset key → true (playable pad). Explicit false stays false for gesture fans.
        if defaults.object(forKey: "classicButtons") == nil {
            classicButtons = true
            defaults.set(true, forKey: "classicButtons")
        } else {
            classicButtons = defaults.bool(forKey: "classicButtons")
        }
        shiftProgress = defaults.integer(forKey: "shiftProgress")
        lastDailyKey = defaults.string(forKey: "lastDailyKey") ?? ""
        lastDailyScore = defaults.integer(forKey: "lastDailyScore")
        cratesReady = defaults.integer(forKey: "cratesReady")
        nextCrateAt = defaults.double(forKey: "nextCrateAt")
        if let mode = defaults.string(forKey: "preferredMode"), let m = PlayModePreference(rawValue: mode) {
            preferredMode = m
        }
    }

    public func persist() {
        defaults.set(scrap, forKey: "scrap")
        defaults.set(gems, forKey: "gems")
        defaults.set(highScore, forKey: "highScore")
        defaults.set(endlessHighScore, forKey: "endlessHighScore")
        defaults.set(playerLevel, forKey: "playerLevel")
        defaults.set(xp, forKey: "xp")
        defaults.set(dailyStreak, forKey: "dailyStreak")
        defaults.set(lastStreakDayKey, forKey: "lastStreakDayKey")
        defaults.set(streakSavers, forKey: "streakSavers")
        defaults.set(streakSaverWeekKey, forKey: "streakSaverWeekKey")
        defaults.set(firstWin, forKey: "firstWin")
        defaults.set(sessionCount, forKey: "sessionCount")
        defaults.set(notifAsked, forKey: "notifAsked")
        defaults.set(adsRemoved, forKey: "adsRemoved")
        defaults.set(premiumPass, forKey: "premiumPass")
        defaults.set(battlePassXP, forKey: "battlePassXP")
        defaults.set(tutorialDone, forKey: "tutorialDone")
        defaults.set(classicButtons, forKey: "classicButtons")
        defaults.set(shiftProgress, forKey: "shiftProgress")
        defaults.set(lastDailyKey, forKey: "lastDailyKey")
        defaults.set(lastDailyScore, forKey: "lastDailyScore")
        defaults.set(cratesReady, forKey: "cratesReady")
        defaults.set(nextCrateAt, forKey: "nextCrateAt")
        defaults.set(preferredMode.rawValue, forKey: "preferredMode")
    }

    public func addScrap(_ n: Int) {
        scrap += max(0, n)
        persist()
    }

    public func addGems(_ n: Int) {
        gems += max(0, n)
        persist()
    }

    public func consumeShotMode() -> String? {
        let s = shotMode
        shotMode = nil
        return s
    }

    nonisolated public static func streakScrap(forDay day: Int) -> Int { min(200, 10 + day * 8) }
    nonisolated public static func streakGems(forDay day: Int) -> Int {
        day > 0 && day % 7 == 0 ? 5 : (day >= 3 ? 1 : 0)
    }

    @discardableResult
    public func registerDailyActivity(dayKey: String = PlayerProfile.utcDayKey()) -> (streak: Int, scrap: Int, gems: Int, isNew: Bool) {
        if lastStreakDayKey == dayKey {
            return (dailyStreak, 0, 0, false)
        }
        if !lastStreakDayKey.isEmpty, lastStreakDayKey != previousDayKey(of: dayKey) {
            if streakSavers > 0 {
                streakSavers -= 1
            } else {
                dailyStreak = 0
            }
        }
        dailyStreak += 1
        lastStreakDayKey = dayKey
        let s = Self.streakScrap(forDay: dailyStreak)
        let g = Self.streakGems(forDay: dailyStreak)
        scrap += s
        gems += g
        persist()
        return (dailyStreak, s, g, true)
    }

    private func previousDayKey(of key: String) -> String {
        guard key.count == 8, let y = Int(key.prefix(4)), let m = Int(key.dropFirst(4).prefix(2)), let d = Int(key.suffix(2)) else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        guard let date = cal.date(from: comps),
              let prev = cal.date(byAdding: .day, value: -1, to: date) else { return "" }
        return Self.utcDayKey(for: prev)
    }

    public func refreshStreakSaverWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let week = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.yearForWeekOfYear, from: Date())
        let key = "\(year)-W\(week)"
        if streakSaverWeekKey != key {
            streakSaverWeekKey = key
            streakSavers = 1
            persist()
        }
    }

    public func refreshCrateClock(now: TimeInterval = Date().timeIntervalSince1970) {
        if nextCrateAt <= 0 {
            nextCrateAt = now + 4 * 3600
            persist()
            return
        }
        var advanced = false
        while nextCrateAt <= now, cratesReady < 2 {
            cratesReady += 1
            nextCrateAt += 4 * 3600
            advanced = true
        }
        if cratesReady >= 2 {
            nextCrateAt = now + 4 * 3600
        }
        if advanced { persist() }
    }

    public var secondsUntilNextCrate: TimeInterval {
        refreshCrateClock()
        if cratesReady >= 2 { return 0 }
        return max(0, nextCrateAt - Date().timeIntervalSince1970)
    }

    /// Bump once per cold launch (call from app entry).
    public func noteSessionLaunch() {
        sessionCount += 1
        persist()
    }

    /// True once the player has opened settings on/after their 2nd session.
    public var mayPromptNotifications: Bool {
        sessionCount >= 2 && !notifAsked
    }

    @discardableResult
    public func openCrate() -> (scrap: Int, gems: Int)? {
        refreshCrateClock()
        guard cratesReady > 0 else { return nil }
        cratesReady -= 1
        let loot = CrateLoot.roll()
        scrap += loot.scrap
        gems += loot.gems
        persist()
        return loot
    }

    public func markDailyComplete(score: Int) {
        let key = Self.utcDayKey()
        lastDailyKey = key
        lastDailyScore = score
        _ = registerDailyActivity(dayKey: key)
        persist()
    }

    public var didDailyToday: Bool {
        lastDailyKey == Self.utcDayKey()
    }
}
