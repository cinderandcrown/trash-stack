// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

public struct EconomyConfig: Codable, Sendable {
    public var version: Int
    public var soft: CurrencyDef
    public var premium: PremiumDef
    public var gemPacks: [GemPack]
    public var starterPack: StarterPack
    public var buildings: [String: BuildingDef]
    public var builders: BuildersDef
    public var speedup: SpeedupDef
    public var chests: [String: ChestDef]
    public var loginStreak: LoginStreakDef
    public var spin: SpinDef
    public var notifications: NotificationsDef
    public var ads: AdsDef
    public var oneTimeOffer: OneTimeOfferDef
    public var compliance: ComplianceDef
    public var board: BoardDef
    public var removeAds: RemoveAdsDef
}

public struct CurrencyDef: Codable, Sendable {
    public var id: String
    public var label: String
    public var symbol: String
    public var startAmount: Int
}

public struct PremiumDef: Codable, Sendable {
    public var id: String
    public var label: String
    public var symbol: String
    public var startAmount: Int
    public var rareEarnPerRunCap: Int
}

public struct GemPack: Codable, Sendable {
    public var id: String
    public var gems: Int
    public var priceUsd: Double
    public var productId: String
    public var badge: String?
}

public struct StarterPack: Codable, Sendable {
    public var id: String
    public var label: String
    public var gems: Int
    public var scrap: Int
    public var priceUsd: Double
    public var productId: String
    public var oneTime: Bool
}

public struct BuildingDef: Codable, Sendable {
    public var name: String
    public var maxLevel: Int
    public var levels: [BuildingLevel]
}

public struct BuildingLevel: Codable, Sendable {
    public var cost: Int
    public var sec: Int
    public var perk: [String: Double]
}

public struct BuildersDef: Codable, Sendable {
    public var freeSlots: Int
    public var gemUnlockSlotCost: Int
    public var maxSlots: Int
}

public struct SpeedupDef: Codable, Sendable {
    public var secPerGem: Int
    public var minGems: Int
    public var maxGemsPerAction: Int
}

public struct ChestDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var unlockSec: Int
    public var earnWeight: Int
    public var odds: [OddsRow]
}

public struct OddsRow: Codable, Sendable {
    public var label: String
    public var kind: String
    public var n: Int
    public var pct: Double
}

public struct LoginStreakDef: Codable, Sendable {
    public var capScrap: Int
    public var freezeCostGems: Int
    public var freezeMaxOwned: Int
}

public struct SpinDef: Codable, Sendable {
    public var freePerDay: Int
    public var rewardedExtraPerDay: Int
}

public struct NotificationsDef: Codable, Sendable {
    public var askAfterFirstWin: Bool
    public var neverAtLaunch: Bool
    public var maxPerDay: Int
    public var quietHours: QuietHours
    public var kinds: [String]
}

public struct QuietHours: Codable, Sendable {
    public var start: Int
    public var end: Int
}

public struct AdsDef: Codable, Sendable {
    public var interstitialEveryNOvers: Int
    public var interstitialSkipFirstRuns: Int
    public var bannersInPlay: Bool
    public var rewarded: [String]
}

public struct OneTimeOfferDef: Codable, Sendable {
    public var enabled: Bool
    public var maxPerSession: Int
    public var maxSurfacesPerDay: Int
    public var neverReshowSameDay: Bool
    public var cooldownHours: Int
    public var quietHours: QuietHours
    public var allowContexts: [String]
    public var denyContexts: [String]
    public var placements: [String]
    public var dismissOneTap: Bool
    public var fakeCountdownTimers: Bool
    public var confirmshaming: Bool
    public var bannedCopyPatterns: [String]
    public var rewardedAdsOptInOnly: Bool
    public var freeToPlayComplete: Bool
}

public struct ComplianceDef: Codable, Sendable {
    public var maxAgeRating: String
    public var noRealMoneyGambling: Bool
    public var noCashOut: Bool
    public var showOddsForRandom: Bool
    public var noPaidLootWithoutOdds: Bool
    public var noDarkPatternsAimedAtKids: Bool
    public var noPurchaseNagging: Bool
    public var freeToPlayComplete: Bool
    public var rewardedAdsOptInOnly: Bool
}

public struct BoardDef: Codable, Sendable {
    public var cols: Int
    public var visibleRows: Int
    public var hiddenRows: Int
}

public struct RemoveAdsDef: Codable, Sendable {
    public var productId: String
    public var priceUsd: Double
    public var stub: Bool
}

public struct SeasonConfig: Codable, Sendable {
    public var id: Int
    public var slug: String
    public var name: String
    public var label: String
    public var tiers: Int
    public var xpPerTier: Int
    public var theme: SeasonTheme?
    public var premiumPurchase: PremiumPurchase
    public var bundle: PassBundle
    public var tierBuy: TierBuy
    public var free: [SeasonReward]
    public var premium: [SeasonReward]
    public var legendary: LegendaryReward
    public var xpSources: [String]
}

public struct SeasonTheme: Codable, Sendable {
    public var tagline: String?
    public var primary: String?
    public var accent: String?
}

public struct PremiumPurchase: Codable, Sendable {
    public var priceUsd: Double
    public var gemCost: Int
    public var productId: String
    public var stub: Bool
}

public struct PassBundle: Codable, Sendable {
    public var id: String
    public var label: String
    public var priceUsd: Double
    public var gemCost: Int
    public var tierSkip: Int
    public var productId: String
    public var stub: Bool
}

public struct TierBuy: Codable, Sendable {
    public var enabled: Bool
    public var gemsPerTier: Int
    public var neverPushed: Bool
    public var maxBuyPerSession: Int
}

public struct SeasonReward: Codable, Sendable {
    public var at: Int
    public var scrap: Int?
    public var gems: Int?
    public var trail: String?
    public var bg: String?
    public var skin: String?
    public var skinSet: String?
    public var outfit: String?
    public var emote: String?
    public var banner: String?
    public var crushFx: String?
    public var legendaryStyle: String?
    public var animated: Bool?
    public var legendary: Bool?
}

public struct LegendaryReward: Codable, Sendable {
    public var at: Int
    public var track: String
    public var id: String
    public var kind: String
    public var animated: Bool
    public var label: String
    public var styles: [LegendaryStyle]
}

public struct LegendaryStyle: Codable, Sendable {
    public var id: String
    public var unlockAt: Int
    public var label: String
}

public struct SeasonIndex: Codable, Sendable {
    public var activeSeasonId: Int
    public var seasons: [String]
}
