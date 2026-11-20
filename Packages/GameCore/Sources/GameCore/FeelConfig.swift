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
    /// Delay before left/right auto-repeat starts (classic pad hold).
    public var dasDelaySec: Double
    /// Interval between auto-repeat moves while held.
    public var arrIntervalSec: Double
    /// Soft-drop repeat while SOFT is held.
    public var softRepeatSec: Double

    /// Keep in sync with Resources/feel.json — a load miss must not quiet the juice.
    public static let fallback = FeelConfig(
        gravityBaseSec: 0.68,
        gravityMinSec: 0.11,
        gravityLevelStep: 0.048,
        lockDelaySec: 0.50,
        fallLerpLateral: 42,
        fallLerpVertical: 30,
        recycleSuckSec: 0.34,
        settleBounceSec: 0.10,
        pressSlamDownSec: 0.12,
        pressSlamUpSec: 0.16,
        hitStopShortSec: 0.07,
        hitStopComboSec: 0.14,
        shakeRecycle: 16,
        shakePress: 24,
        flashCooldownSec: 0.07,
        nearMissRows: 3,
        dasDelaySec: 0.16,
        arrIntervalSec: 0.045,
        softRepeatSec: 0.045
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
