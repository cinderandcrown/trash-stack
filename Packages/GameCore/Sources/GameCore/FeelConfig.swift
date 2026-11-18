// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Tunable feel numbers — loaded from Resources/feel.json. No magic numbers in scenes.
public struct FeelConfig: Codable, Sendable, Equatable {
    public var gravityBaseSec: Double
    public var gravityMinSec: Double
    public var gravityLevelStep: Double
    public var lockDelaySec: Double
    public var fallLerpLateral: Double
    public var fallLerpVertical: Double
    public var recycleSuckSec: Double
    public var settleBounceSec: Double
    public var pressSlamDownSec: Double
    public var pressSlamUpSec: Double
    public var hitStopShortSec: Double
    public var hitStopComboSec: Double
    public var shakeRecycle: Double
    public var shakePress: Double
    public var flashCooldownSec: Double
    public var nearMissRows: Int

    /// Keep in sync with Resources/feel.json — a load miss must not quiet the juice.
    public static let fallback = FeelConfig(
        gravityBaseSec: 0.62,
        gravityMinSec: 0.12,
        gravityLevelStep: 0.03,
        lockDelaySec: 0.45,
        fallLerpLateral: 32,
        fallLerpVertical: 22,
        recycleSuckSec: 0.42,
        settleBounceSec: 0.14,
        pressSlamDownSec: 0.16,
        pressSlamUpSec: 0.2,
        hitStopShortSec: 0.07,
        hitStopComboSec: 0.13,
        shakeRecycle: 12,
        shakePress: 18,
        flashCooldownSec: 0.1,
        nearMissRows: 3
    )
}

/// One gym entry per system — deterministic setups for isolated feel work.
public enum BoardGym: String, Sendable, CaseIterable {
    case board
    case clusters
    case press
    case snatch
    case tickets

    public var shotName: String {
        switch self {
        case .board: return "game"
        case .clusters: return "recycle"
        case .press: return "compactor"
        case .snatch: return "snatch"
        case .tickets: return "tickets"
        }
    }

    public var label: String {
        switch self {
        case .board: return "Board + spawner"
        case .clusters: return "Clusters"
        case .press: return "Press"
        case .snatch: return "Snatch"
        case .tickets: return "Tickets"
        }
    }
}
