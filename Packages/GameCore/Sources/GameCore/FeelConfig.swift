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

    public static let fallback = FeelConfig(
        gravityBaseSec: 0.62,
        gravityMinSec: 0.12,
        gravityLevelStep: 0.03,
        lockDelaySec: 0.45,
        fallLerpLateral: 18,
        fallLerpVertical: 14,
        recycleSuckSec: 0.25,
        settleBounceSec: 0.16,
        pressSlamDownSec: 0.18,
        pressSlamUpSec: 0.22,
        hitStopShortSec: 0.04,
        hitStopComboSec: 0.09,
        shakeRecycle: 6,
        shakePress: 12,
        flashCooldownSec: 0.12,
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
