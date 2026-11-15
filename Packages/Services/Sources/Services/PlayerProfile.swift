// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
#if canImport(Combine)
import Combine
#endif

@MainActor
public final class PlayerProfile: ObservableObject {
    public static let shared = PlayerProfile()

    @Published public var scrap: Int = 80
    @Published public var gems: Int = 20
    @Published public var highScore: Int = 0
    @Published public var playerLevel: Int = 1
    @Published public var xp: Int = 0
    @Published public var dailyStreak: Int = 0
    @Published public var firstWin: Bool = false
    @Published public var notifAsked: Bool = false
    @Published public var adsRemoved: Bool = false
    @Published public var premiumPass: Bool = false
    @Published public var battlePassXP: Int = 0
    @Published public var tutorialDone: Bool = false
    @Published public var classicButtons: Bool = false
    @Published public var baseLevels: [String: Int] = [
        "recycler": 1, "compactor": 1, "neonSign": 1, "stashVault": 1,
    ]
    @Published public var shotMode: String? = nil

    private let defaults = UserDefaults.standard

    public init() {
        load()
        // Launch-arg wins (simctl): -trashStackShot <mode>
        if let arg = Self.shotArgument() {
            shotMode = arg
        } else if let shot = defaults.string(forKey: "trashStack.shot"), !shot.isEmpty {
            shotMode = shot
            defaults.removeObject(forKey: "trashStack.shot")
        }
    }

    /// Prefer `simctl launch … -trashStackShot recycle` over defaults write (more reliable in CI).
    public static func shotArgument() -> String? {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-trashStackShot"), idx + 1 < args.count {
            let v = args[idx + 1]
            return v.isEmpty ? nil : v
        }
        return nil
    }

    public func load() {
        scrap = defaults.object(forKey: "scrap") as? Int ?? 80
        gems = defaults.object(forKey: "gems") as? Int ?? 20
        highScore = defaults.integer(forKey: "highScore")
        playerLevel = max(1, defaults.integer(forKey: "playerLevel"))
        xp = defaults.integer(forKey: "xp")
        dailyStreak = defaults.integer(forKey: "dailyStreak")
        firstWin = defaults.bool(forKey: "firstWin")
        notifAsked = defaults.bool(forKey: "notifAsked")
        adsRemoved = defaults.bool(forKey: "adsRemoved")
        premiumPass = defaults.bool(forKey: "premiumPass")
        battlePassXP = defaults.integer(forKey: "battlePassXP")
        tutorialDone = defaults.bool(forKey: "tutorialDone")
        classicButtons = defaults.bool(forKey: "classicButtons")
    }

    public func persist() {
        defaults.set(scrap, forKey: "scrap")
        defaults.set(gems, forKey: "gems")
        defaults.set(highScore, forKey: "highScore")
        defaults.set(playerLevel, forKey: "playerLevel")
        defaults.set(xp, forKey: "xp")
        defaults.set(dailyStreak, forKey: "dailyStreak")
        defaults.set(firstWin, forKey: "firstWin")
        defaults.set(notifAsked, forKey: "notifAsked")
        defaults.set(adsRemoved, forKey: "adsRemoved")
        defaults.set(premiumPass, forKey: "premiumPass")
        defaults.set(battlePassXP, forKey: "battlePassXP")
        defaults.set(tutorialDone, forKey: "tutorialDone")
        defaults.set(classicButtons, forKey: "classicButtons")
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
}
