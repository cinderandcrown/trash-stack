// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

public enum EconomyMath {
    public static func assertOddsSum100(_ odds: [OddsRow], label: String = "odds") throws {
        let sum = odds.reduce(0.0) { $0 + $1.pct }
        if abs(sum - 100) > 0.01 {
            throw EconomyError.oddsSum(label, sum)
        }
    }

    public static func validateChests(_ economy: EconomyConfig) throws {
        for (_, chest) in economy.chests {
            try assertOddsSum100(chest.odds, label: chest.id)
        }
        guard economy.compliance.showOddsForRandom else {
            throw EconomyError.compliance("odds required")
        }
    }

    public static func loginStreakScrap(day: Int, cap: Int) -> Int {
        let d = max(1, day)
        return min(cap, 5 * d + 20 * (d / 7))
    }

    public static func gemsForSpeedup(remainingMs: Int, speedup: SpeedupDef) -> Int {
        let rem = max(0, remainingMs)
        if rem <= 0 { return 0 }
        let sec = Int(ceil(Double(rem) / 1000.0))
        let gems = Int(ceil(Double(sec) / Double(speedup.secPerGem)))
        return min(speedup.maxGemsPerAction, max(speedup.minGems, gems))
    }

    public static func sumPremiumGems(_ season: SeasonConfig) -> Int {
        season.premium.reduce(0) { $0 + ($1.gems ?? 0) }
    }

    public static func premiumPayback(_ season: SeasonConfig) -> (cost: Int, earned: Int, paysBack: Bool) {
        let cost = season.premiumPurchase.gemCost
        let earned = sumPremiumGems(season)
        return (cost, earned, earned > cost)
    }

    public static func assertSeasonShape(_ season: SeasonConfig) throws {
        guard (50...100).contains(season.tiers) else {
            throw EconomyError.season("tiers must be 50–100")
        }
        guard season.free.count == season.tiers, season.premium.count == season.tiers else {
            throw EconomyError.season("track length mismatch")
        }
        guard season.legendary.at == season.tiers else {
            throw EconomyError.season("legendary at max tier")
        }
        guard season.legendary.styles.count >= 2 else {
            throw EconomyError.season("progressive styles required")
        }
        let pay = premiumPayback(season)
        guard pay.paysBack else {
            throw EconomyError.season("premium gems must exceed cost")
        }
        guard season.bundle.tierSkip == 25 else {
            throw EconomyError.season("Pass + 25 required")
        }
        guard season.tierBuy.neverPushed else {
            throw EconomyError.season("tierBuy never pushed")
        }
    }

    public static func assertOfferCaps(_ offer: OneTimeOfferDef) throws {
        guard offer.maxPerSession == 1 else { throw EconomyError.offer("maxPerSession") }
        guard offer.maxSurfacesPerDay == 1 else { throw EconomyError.offer("maxSurfacesPerDay") }
        guard offer.neverReshowSameDay else { throw EconomyError.offer("neverReshowSameDay") }
        guard offer.fakeCountdownTimers == false else { throw EconomyError.offer("fake timers") }
        guard offer.confirmshaming == false else { throw EconomyError.offer("confirmshaming") }
        guard offer.denyContexts.contains("launch"),
              offer.denyContexts.contains("mid_run"),
              offer.denyContexts.contains("after_loss") else {
            throw EconomyError.offer("denyContexts")
        }
        guard offer.allowContexts.contains("after_win"),
              offer.allowContexts.contains("after_level_up") else {
            throw EconomyError.offer("allowContexts")
        }
    }

    public static func canSurfaceOffer(
        context: String,
        sessionSurfaces: Int,
        daySurfaces: Int,
        dismissedDay: String?,
        dayKey: String,
        offer: OneTimeOfferDef
    ) -> (ok: Bool, reason: String) {
        guard offer.enabled else { return (false, "disabled") }
        if offer.denyContexts.contains(context) { return (false, "denied_context") }
        if context == "shop" { return (true, "shop_catalog") }
        guard offer.allowContexts.contains(context) else { return (false, "context") }
        if offer.neverReshowSameDay, dismissedDay == dayKey { return (false, "dismissed_today") }
        if daySurfaces >= offer.maxSurfacesPerDay { return (false, "day_cap") }
        if sessionSurfaces >= offer.maxPerSession { return (false, "session_cap") }
        return (true, "allowed")
    }

    public static func seasonTier(xp: Int, xpPerTier: Int, maxTier: Int) -> Int {
        Swift.min(maxTier, Swift.max(0, xp / xpPerTier))
    }

    public static func pickWeightedChest(chests: [String: ChestDef], unit: Double) -> String {
        let list = Array(chests.values)
        let total = list.reduce(0) { $0 + $1.earnWeight }
        var r = unit * Double(total)
        for c in list {
            r -= Double(c.earnWeight)
            if r <= 0 { return c.id }
        }
        return list.last?.id ?? "dock_crate"
    }
}

public enum EconomyError: Error, Sendable {
    case oddsSum(String, Double)
    case compliance(String)
    case season(String)
    case offer(String)
}
