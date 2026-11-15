// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
#if canImport(Combine)
import Combine
#endif

#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
public final class NotificationService: ObservableObject {
    public static let shared = NotificationService()

    @Published public var authorized = false
    public var sentToday = 0
    public var sentDate = ""
    public var quietHours = true
    public var enabled: [String: Bool] = [
        "upgrade_done": true, "chest_ready": true, "daily_reward": true,
        "streak_risk": true, "new_season": true,
    ]

    public func refreshStatus() async {
#if canImport(UserNotifications)
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
#else
        authorized = false
#endif
    }

    /// Ask only after first win — never at launch.
    public func requestAfterFirstWin() async -> Bool {
#if canImport(UserNotifications)
        let ok = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
        return ok == true
#else
        return false
#endif
    }

    public func schedule(kind: String, title: String, body: String, afterSeconds: TimeInterval = 2, maxPerDay: Int = 2) async {
        guard enabled[kind] != false else { return }
        if quietHours, inQuietHours() { return }
        let day = Self.dayKey(Date())
        if sentDate != day { sentToday = 0; sentDate = day }
        guard sentToday < maxPerDay else { return }
#if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1.5, afterSeconds), repeats: false)
        let req = UNNotificationRequest(identifier: "ts-\(kind)-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
#endif
        sentToday += 1
    }

    private func inQuietHours() -> Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 21 || h < 8
    }

    nonisolated public static func dayKey(_ date: Date) -> String {
        let c = Calendar.current
        return String(format: "%04d-%02d-%02d", c.component(.year, from: date), c.component(.month, from: date), c.component(.day, from: date))
    }
}
