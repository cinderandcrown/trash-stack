// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
#if canImport(Combine)
import Combine
#endif

#if canImport(GameKit)
import GameKit
#endif

/// GameKit leaderboards / achievements — stubbed when entitlement / auth missing.
@MainActor
public final class GameKitService: ObservableObject {
    public static let shared = GameKitService()
    @Published public private(set) var authenticated = false
    public var stubMode = true

    public func authenticate() async {
#if canImport(GameKit)
        // Interactive Game Center sign-in is entitlement-gated. CI / local builds without
        // the capability stay in stub mode; live sessions reuse an existing auth state.
        authenticated = GKLocalPlayer.local.isAuthenticated
        stubMode = !authenticated
#else
        authenticated = false
        stubMode = true
#endif
    }

    public func submitScore(_ score: Int, leaderboardID: String = "trashstack_highscore") async {
#if canImport(GameKit)
        guard authenticated, !stubMode else { return }
        try? await GKLeaderboard.submitScore(
            score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID]
        )
#endif
    }

    public func reportAchievement(_ id: String, percent: Double = 100) async {
#if canImport(GameKit)
        guard authenticated, !stubMode else { return }
        let a = GKAchievement(identifier: id)
        a.percentComplete = percent
        try? await GKAchievement.report([a])
#endif
        // Always record locally so CI / stub builds still exercise the path.
        UserDefaults.standard.set(percent, forKey: "gk.achievement.\(id)")
    }
}
