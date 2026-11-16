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

        // Structured Documents mirror — authoritative for smoke when defaults lag.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let body = [
                "in_app_sec=\(dtString)",
                "in_app_sec_string=\(dtString)",
                "first_frame_wall_epoch=\(wallString)",
                "process_start_uptime=\(String(format: "%.6f", start))",
                "first_frame_uptime=\(String(format: "%.6f", nowUptime))",
            ].joined(separator: "\n") + "\n"
            let url = docs.appendingPathComponent("launch-timing.txt")
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
