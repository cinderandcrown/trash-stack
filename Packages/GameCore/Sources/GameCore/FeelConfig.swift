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
        gravityBaseSec: 0.70,
        gravityMinSec: 0.11,
        gravityLevelStep: 0.05,
        lockDelaySec: 0.38,
        fallLerpLateral: 36,
        fallLerpVertical: 26,
        recycleSuckSec: 0.36,
        settleBounceSec: 0.11,
        pressSlamDownSec: 0.14,
        pressSlamUpSec: 0.18,
        hitStopShortSec: 0.08,
        hitStopComboSec: 0.16,
        shakeRecycle: 14,
        shakePress: 20,
        flashCooldownSec: 0.08,
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
