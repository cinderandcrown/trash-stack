// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// One fresh rule that unlocks as the level climbs — keeps the shift interesting.
public enum LevelTwist: Int, Sendable, CaseIterable, Equatable {
    case nightWarmup = 1
    case quickerFall = 2
    case stickyCans = 3
    case leakingPipes = 4
    case denseJunk = 5
    case alleyGusts = 6
    case nightRush = 7

    public static func active(at level: Int) -> LevelTwist {
        let clamped = max(1, min(7, level))
        return LevelTwist(rawValue: clamped) ?? .nightRush
    }

    /// Short line shown on level-up so the player feels the new rule.
    public var playerBlurb: String {
        switch self {
        case .nightWarmup: return "Night shift open"
        case .quickerFall: return "Fall speeds up"
        case .stickyCans: return "Sticky cans appear"
        case .leakingPipes: return "Pipes leak — convert neighbors"
        case .denseJunk: return "Heavier junk in the bag"
        case .alleyGusts: return "Alley gusts nudge pieces"
        case .nightRush: return "Lock window tightens"
        }
    }

    /// Compact toast — must fit a phone banner without truncating mid-word.
    public var toastTitle: String {
        "Lv \(rawValue) · \(playerBlurb)"
    }
}
