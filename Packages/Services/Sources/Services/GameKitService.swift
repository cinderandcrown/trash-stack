// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
#if canImport(Combine)
import Combine
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(GameKit)
@preconcurrency import GameKit
#endif
import GameCore

/// Game Center auth, leaderboards, achievements, TRASH TALK matchmaking.
/// Fully playable signed out — GC features no-op in stub mode.
@MainActor
public final class GameKitService: NSObject, ObservableObject {
    public static let shared = GameKitService()

    @Published public private(set) var authenticated = false
    @Published public private(set) var playerDisplayName = "Night Shift"
    @Published public private(set) var matchmaking = false
    @Published public private(set) var matchError: String?
#if canImport(UIKit)
    /// Present this from SwiftUI when Game Center wants a sign-in sheet.
    @Published public var authViewController: UIViewController?
#endif

    public var stubMode = true

    #if canImport(GameKit)
    public private(set) var activeMatch: GKMatch?
    #endif

    public var onMatchData: ((Data, String) -> Void)?
    public var onMatchStarted: ((UInt64, Bool /* vsBot */, String /* rival name */) -> Void)?
    public var onMatchEnded: ((Bool /* disconnected */) -> Void)?
    public var onRivalDisconnected: (() -> Void)?

    private var matchmakingTask: Task<Void, Never>?
    private var botFallbackArmed = false
    /// While true, achievement banners stay quiet — queue until end of run.
    private var deferAchievementBanners = false
    private var pendingAchievements: [(id: String, percent: Double)] = []

    /// Call when entering / leaving live play so banners don't cover the HUD mid-run.
    public func setPlayDeferral(_ deferring: Bool) {
        deferAchievementBanners = deferring
#if canImport(GameKit)
        if deferring {
            GKAccessPoint.shared.isActive = false
            GKAccessPoint.shared.showHighlights = false
        }
#endif
        if !deferring {
            Task { await flushPendingAchievements() }
        }
    }

    public func authenticate() async {
#if canImport(GameKit)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish = {
                guard !resumed else { return }
                resumed = true
                cont.resume()
            }
            GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
                let errText = error?.localizedDescription
                Task { @MainActor in
                    guard let self else { finish(); return }
                    // Non-blocking: stash for SwiftUI; game keeps working unsigned.
                    self.authViewController = viewController
                    if let errText {
                        self.matchError = errText
                    }
                    self.authenticated = GKLocalPlayer.local.isAuthenticated
                    self.stubMode = !self.authenticated
                    if self.authenticated {
                        self.playerDisplayName = GKLocalPlayer.local.displayName
                        self.configureAccessPoint(show: false)
                    }
                    finish()
                }
            }
            // Don't hang forever if the handler never fires (CI / no entitlement).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                finish()
            }
        }
#else
        authenticated = false
        stubMode = true
#endif
    }

    public func configureAccessPoint(show: Bool, onResults: Bool = false) {
#if canImport(GameKit)
        guard authenticated else {
            GKAccessPoint.shared.isActive = false
            return
        }
        GKAccessPoint.shared.location = onResults ? .topTrailing : .topLeading
        GKAccessPoint.shared.showHighlights = true
        GKAccessPoint.shared.isActive = show
#endif
    }

    public func submitScore(_ score: Int, leaderboardID: String = TrashTalkRules.leaderboardAllTime) async {
#if canImport(GameKit)
        guard authenticated, !stubMode else { return }
        try? await GKLeaderboard.submitScore(
            score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID]
        )
#endif
    }

    public func submitWeeklyScore(_ score: Int) async {
        await submitScore(score, leaderboardID: TrashTalkRules.leaderboardWeekly)
    }

    public func reportAchievement(_ id: String, percent: Double = 100) async {
        UserDefaults.standard.set(percent, forKey: "gk.achievement.\(id)")
        // Cross-game badge: once Trash Stack unlocks Bandit of Both Worlds, leave a flag
        // Neon City Bandit can read via the shared Game Center group / same achievement id.
        if id == AchievementID.banditOfBothWorlds, percent >= 100 {
            UserDefaults.standard.set(true, forKey: "cc.banditOfBothWorlds.unlocked")
        }
        if deferAchievementBanners {
            // Queue for end-of-run — never flash a banner over the live HUD.
            if let idx = pendingAchievements.firstIndex(where: { $0.id == id }) {
                pendingAchievements[idx].percent = max(pendingAchievements[idx].percent, percent)
            } else {
                pendingAchievements.append((id, percent))
            }
            return
        }
        await reportAchievementNow(id, percent: percent, showBanner: percent >= 100)
    }

    private func reportAchievementNow(_ id: String, percent: Double, showBanner: Bool) async {
#if canImport(GameKit)
        if authenticated, !stubMode {
            let a = GKAchievement(identifier: id)
            a.percentComplete = percent
            a.showsCompletionBanner = showBanner
            try? await GKAchievement.report([a])
        }
#endif
    }

    private func flushPendingAchievements() async {
        let batch = pendingAchievements
        pendingAchievements.removeAll()
        for item in batch {
            await reportAchievementNow(item.id, percent: item.percent, showBanner: item.percent >= 100)
        }
    }

    public func presentLeaderboard(id: String = TrashTalkRules.leaderboardAllTime) {
#if canImport(GameKit)
        guard authenticated else { return }
        let gc = GKGameCenterViewController(leaderboardID: id, playerScope: .global, timeScope: .allTime)
        gc.gameCenterDelegate = self
        topViewController()?.present(gc, animated: true)
#endif
    }

    public func presentAchievements() {
#if canImport(GameKit)
        guard authenticated else { return }
        let gc = GKGameCenterViewController(state: .achievements)
        gc.gameCenterDelegate = self
        topViewController()?.present(gc, animated: true)
#endif
    }

    /// Challenge a friend to beat your score (Game Center challenge sheet when available).
    public func challengeBeatMyScore(_ score: Int, leaderboardID: String = TrashTalkRules.leaderboardAllTime) {
#if canImport(GameKit)
        guard authenticated else { return }
        // Store pending challenge intent; GameKit challenge UI varies by OS — fall back to access point.
        UserDefaults.standard.set(score, forKey: "gk.pendingBeatScore")
        UserDefaults.standard.set(leaderboardID, forKey: "gk.pendingBeatLB")
        configureAccessPoint(show: true)
        presentLeaderboard(id: leaderboardID)
#endif
    }

    // MARK: - TRASH TALK matchmaking

    public func startTrashTalkMatchmaking(inviteFriend: Bool = false) {
#if canImport(GameKit)
        matchError = nil
        matchmaking = true
        botFallbackArmed = true
        matchmakingTask?.cancel()

        if stubMode || !authenticated {
            // No GC — go straight to labeled bot after a short beat (still respects the 20s label).
            matchmakingTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(TrashTalkRules.matchmakingBotFallbackSec * 1_000_000_000))
                guard !Task.isCancelled, self.matchmaking else { return }
                self.startBotMatch(reason: "offline")
            }
            return
        }

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.inviteMessage = "TRASH TALK — last bin standing!"

        if inviteFriend {
            let picker = GKMatchmakerViewController(matchRequest: request)
            picker?.matchmakerDelegate = self
            if let picker {
                topViewController()?.present(picker, animated: true)
            }
        } else {
            GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
                let errText = error?.localizedDescription
                // GameKit types are not Sendable; hop with an unchecked capture.
                nonisolated(unsafe) let found = match
                Task { @MainActor in
                    guard let self else { return }
                    if let errText {
                        self.matchError = errText
                    }
                    if let found {
                        self.attach(match: found)
                    }
                }
            }
        }

        matchmakingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TrashTalkRules.matchmakingBotFallbackSec * 1_000_000_000))
            guard !Task.isCancelled, self.matchmaking, self.activeMatch == nil else { return }
            GKMatchmaker.shared().cancel()
            self.startBotMatch(reason: "timeout")
        }
#else
        matchmaking = true
        matchmakingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TrashTalkRules.matchmakingBotFallbackSec * 1_000_000_000))
            self.startBotMatch(reason: "unsupported")
        }
#endif
    }

    public func cancelMatchmaking() {
        matchmakingTask?.cancel()
        matchmaking = false
#if canImport(GameKit)
        GKMatchmaker.shared().cancel()
#endif
    }

    public func startBotMatch(reason: String = "fallback") {
        matchmakingTask?.cancel()
        matchmaking = false
        botFallbackArmed = false
#if canImport(GameKit)
        activeMatch = nil
#endif
        let seed = UInt64.random(in: 1...UInt64.max)
        onMatchStarted?(seed, true, "Dumpster Bot")
        matchError = nil
        _ = reason
    }

    public func send(_ message: TrashTalkWire) {
#if canImport(GameKit)
        guard let match = activeMatch else { return }
        let data = message.encode()
        try? match.sendData(toAllPlayers: data, with: .reliable)
#endif
    }

    public func disconnectMatch() {
#if canImport(GameKit)
        activeMatch?.disconnect()
        activeMatch = nil
#endif
        matchmaking = false
    }

#if canImport(GameKit)
    private func attach(match: GKMatch) {
        matchmakingTask?.cancel()
        matchmaking = false
        activeMatch = match
        match.delegate = self
        let rivals = match.players.map(\.displayName)
        let rivalName = rivals.first ?? "Rival"
        // Shared seed from sorted player IDs so both devices agree without an extra round-trip.
        let ids = ([GKLocalPlayer.local.gamePlayerID] + match.players.map(\.gamePlayerID)).sorted()
        var seed: UInt64 = 0x9e37_79b9_7f4a_7c15
        for id in ids {
            for b in id.utf8 {
                seed ^= UInt64(b)
                seed &*= 0x100_0000_01b3
            }
        }
        if seed == 0 { seed = 1 }
        send(.hello(seed: seed))
        onMatchStarted?(seed, false, rivalName)
    }
#endif

#if canImport(UIKit)
    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
#endif
}

#if canImport(GameKit)
extension GameKitService: GKGameCenterControllerDelegate {
    public nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        Task { @MainActor in
            gameCenterViewController.dismiss(animated: true)
        }
    }
}

extension GameKitService: GKMatchmakerViewControllerDelegate {
    public nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        Task { @MainActor in
            viewController.dismiss(animated: true)
            self.cancelMatchmaking()
        }
    }

    public nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        let errText = error.localizedDescription
        Task { @MainActor in
            viewController.dismiss(animated: true)
            self.matchError = errText
            self.matchmaking = false
        }
    }

    public nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        // GKMatch is not Sendable under Swift 6 — unchecked hop to MainActor.
        nonisolated(unsafe) let found = match
        Task { @MainActor in
            viewController.dismiss(animated: true)
            self.attach(match: found)
        }
    }
}

extension GameKitService: GKMatchDelegate {
    public nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let payload = data
        let name = player.displayName
        Task { @MainActor in
            self.onMatchData?(payload, name)
        }
    }

    public nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let disconnected = state == .disconnected
        Task { @MainActor in
            if disconnected {
                self.onRivalDisconnected?()
                self.onMatchEnded?(true)
            }
        }
    }

    public nonisolated func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        let errText = error?.localizedDescription
        Task { @MainActor in
            self.matchError = errText
            self.onMatchEnded?(true)
        }
    }
}
#endif
