// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Honest cold-launch instrumentation: process start → first interactive frame
/// (publisher ident on cold launch, or Trash Stack title when the ident is skipped).
///
/// Smoke reads:
/// - `trashStack.launchToTitleSec` / Documents `in_app_sec` → in-app ≤ 1.5s (authoritative)
/// - Documents `first_frame_wall_epoch` vs host stamp at `simctl launch` PID → wall ≤ 8s
enum LaunchTiming {
    /// Process-start stamp must be set from `@main` init (may be nonisolated).
    nonisolated(unsafe) private static var processStartUptime: TimeInterval = 0
    nonisolated(unsafe) private static var didMarkTitle = false
    nonisolated(unsafe) private static var playTapUptime: TimeInterval = 0
    nonisolated(unsafe) private static var didMarkGame = false

    /// Call from `@main` init — safe from any isolation.
    nonisolated static func bootstrap() {
        if processStartUptime == 0 {
            processStartUptime = ProcessInfo.processInfo.systemUptime
        }
    }

    /// Call from the first interactive paint (`PublisherIdentView` / `TitleView` / `RootView`).
    @MainActor
    static func markFirstTitleFrame() {
        bootstrap()
        guard !didMarkTitle else { return }
        didMarkTitle = true
        let start = processStartUptime
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let dt = max(0, nowUptime - start)
        // Absolute wall clock shared with the smoke host (same Mac for Simulator).
        let wallEpoch = Date().timeIntervalSince1970
        let dtString = String(format: "%.4f", dt)
        let wallString = String(format: "%.6f", wallEpoch)

        let defaults = UserDefaults.standard
        defaults.set(dt, forKey: "trashStack.launchToTitleSec")
        defaults.set(dtString, forKey: "trashStack.launchToTitleSecString")
        defaults.set(start, forKey: "trashStack.processStartUptime")
        defaults.set(nowUptime, forKey: "trashStack.titleFrameUptime")
        defaults.set(wallEpoch, forKey: "trashStack.firstFrameWallEpoch")
        defaults.set(wallString, forKey: "trashStack.firstFrameWallEpochString")
        defaults.synchronize()

        writeDocsMirror(inApp: dtString, wall: wallString, start: start, first: nowUptime, kind: "title")
    }

    /// Call when the player taps PLAY / enters the game path.
    @MainActor
    static func markPlayTap() {
        playTapUptime = ProcessInfo.processInfo.systemUptime
        UserDefaults.standard.set(playTapUptime, forKey: "trashStack.playTapUptime")
        UserDefaults.standard.synchronize()
    }

    /// Call after the first rendered CompactorScene frame (board backdrop + cells).
    /// Gates: ≤1.5s after PLAY tap, and ≤8s wall from process launch for demo path.
    @MainActor
    static func markFirstGameFrame() {
        bootstrap()
        guard !didMarkGame else { return }
        didMarkGame = true
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let tap = playTapUptime > 0 ? playTapUptime : processStartUptime
        let dt = max(0, nowUptime - tap)
        let wallEpoch = Date().timeIntervalSince1970
        let dtString = String(format: "%.4f", dt)
        let wallString = String(format: "%.6f", wallEpoch)
        let defaults = UserDefaults.standard
        defaults.set(dt, forKey: "trashStack.launchToGameSec")
        defaults.set(dtString, forKey: "trashStack.launchToGameSecString")
        defaults.set(wallEpoch, forKey: "trashStack.firstGameFrameWallEpoch")
        defaults.set(wallString, forKey: "trashStack.firstGameFrameWallEpochString")
        defaults.synchronize()
        // Append game-path lines only — never clobber title cold-launch stamps.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent("launch-timing.txt")
            let extra = [
                "game_in_app_sec=\(dtString)",
                "game_first_frame_wall_epoch=\(wallString)",
                "stamp_kind_game=game",
            ].joined(separator: "\n") + "\n"
            if let existing = try? String(contentsOf: url, encoding: .utf8) {
                try? (existing + extra).write(to: url, atomically: true, encoding: .utf8)
            } else {
                try? extra.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    @MainActor
    private static func writeDocsMirror(inApp: String, wall: String, start: TimeInterval, first: TimeInterval, kind: String) {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let body = [
                "in_app_sec=\(inApp)",
                "in_app_sec_string=\(inApp)",
                "first_frame_wall_epoch=\(wall)",
                "process_start_uptime=\(String(format: "%.6f", start))",
                "first_frame_uptime=\(String(format: "%.6f", first))",
                "stamp_kind=\(kind)",
            ].joined(separator: "\n") + "\n"
            let url = docs.appendingPathComponent("launch-timing.txt")
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
