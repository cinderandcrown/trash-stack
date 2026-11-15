// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import Services

final class ServicesTests: XCTestCase {
    func testDayKeyFormat() {
        let key = NotificationService.dayKey(Date(timeIntervalSince1970: 1_000_000))
        XCTAssertFalse(key.isEmpty)
        XCTAssertEqual(key.count, 10)
    }

    func testStreakRewardHelpers() {
        XCTAssertEqual(PlayerProfile.streakScrap(forDay: 1), 18)
        XCTAssertEqual(PlayerProfile.streakScrap(forDay: 7), 66)
        XCTAssertEqual(PlayerProfile.streakGems(forDay: 7), 5)
        XCTAssertEqual(PlayerProfile.utcDayKey().count, 8)
    }

    func testStreakAndCrateRetention() async {
        await MainActor.run {
            let p = PlayerProfile()
            p.dailyStreak = 0
            p.lastStreakDayKey = ""
            p.streakSavers = 1
            p.cratesReady = 0
            p.nextCrateAt = Date().timeIntervalSince1970 - 1
            p.refreshCrateClock()
            XCTAssertGreaterThanOrEqual(p.cratesReady, 1)
            XCTAssertLessThanOrEqual(p.cratesReady, 2)
            let first = p.registerDailyActivity(dayKey: "20990101")
            XCTAssertTrue(first.isNew)
            XCTAssertEqual(first.streak, 1)
            XCTAssertGreaterThan(first.scrap, 0)
            let again = p.registerDailyActivity(dayKey: "20990101")
            XCTAssertFalse(again.isNew)
        }
    }
}
