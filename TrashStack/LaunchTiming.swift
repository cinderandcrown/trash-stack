// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Honest cold-launch instrumentation: process start → first interactive frame
/// (publisher ident on cold launch, or Trash Stack title when the ident is skipped).
/// Smoke reads `trashStack.launchToTitleSec` (and Documents/launch-timing.txt) and asserts ≤ 1.5s.
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
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0, now - start)
        let defaults = UserDefaults.standard
        defaults.set(dt, forKey: "trashStack.launchToTitleSec")
        defaults.set(start, forKey: "trashStack.processStartUptime")
        defaults.set(now, forKey: "trashStack.titleFrameUptime")
        let asString = String(format: "%.4f", dt)
        defaults.set(asString, forKey: "trashStack.launchToTitleSecString")
        defaults.synchronize()
        // Mirror to Documents so smoke can read via get_app_container if defaults lag.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent("launch-timing.txt")
            try? asString.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
