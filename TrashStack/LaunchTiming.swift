// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Honest cold-launch instrumentation: process start → first title frame.
/// Smoke reads `trashStack.launchToTitleSec` and asserts ≤ 1.5s.
@MainActor
enum LaunchTiming {
    /// Captured at first access — call `bootstrap()` from `@main` init.
    private(set) static var processStartUptime: TimeInterval = 0
    private static var didMarkTitle = false

    static func bootstrap() {
        if processStartUptime == 0 {
            processStartUptime = ProcessInfo.processInfo.systemUptime
        }
    }

    /// Call from the first interactive title paint (`TitleView.onAppear`).
    static func markFirstTitleFrame() {
        bootstrap()
        guard !didMarkTitle else { return }
        didMarkTitle = true
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0, now - processStartUptime)
        let defaults = UserDefaults.standard
        defaults.set(dt, forKey: "trashStack.launchToTitleSec")
        defaults.set(processStartUptime, forKey: "trashStack.processStartUptime")
        defaults.set(now, forKey: "trashStack.titleFrameUptime")
        // Also mirror as a string for easy `defaults read` in smoke.
        defaults.set(String(format: "%.4f", dt), forKey: "trashStack.launchToTitleSecString")
    }
}
