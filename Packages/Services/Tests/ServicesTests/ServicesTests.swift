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

    func testCrateOddsDisplayMatchesRollTable() {
        // Displayed line is generated from the same table the roll uses.
        XCTAssertEqual(CrateLoot.gemOutcomes, [0, 1, 2])
        XCTAssertEqual(CrateLoot.scrapMin, 40)
        XCTAssertEqual(CrateLoot.scrapMax, 80)
        XCTAssertEqual(CrateLoot.scrapChancePercent, 100)
        // 2 of 3 outcomes grant gems → ~66.7%, never a hard-coded 18%.
        XCTAssertEqual(CrateLoot.bonusGemsChancePercent, 100.0 * 2.0 / 3.0, accuracy: 0.01)
        let line = CrateLoot.oddsDisplayLine
        XCTAssertTrue(line.contains("40–80") || line.contains("40-80"))
        XCTAssertTrue(line.contains("100%"))
        XCTAssertTrue(line.contains("0 ("))
        XCTAssertTrue(line.contains("1 ("))
        XCTAssertTrue(line.contains("2 ("))
        XCTAssertFalse(line.contains("18%"))

        var gemHistogram = [0: 0, 1: 0, 2: 0]
        for i in 0..<300 {
            let loot = CrateLoot.roll(
                scrapRandom: { _ in i % 41 },
                gemIndexRandom: { _ in i % 3 }
            )
            XCTAssertGreaterThanOrEqual(loot.scrap, CrateLoot.scrapMin)
            XCTAssertLessThanOrEqual(loot.scrap, CrateLoot.scrapMax)
            XCTAssertTrue(CrateLoot.gemOutcomes.contains(loot.gems))
            gemHistogram[loot.gems, default: 0] += 1
        }
        XCTAssertEqual(gemHistogram[0], 100)
        XCTAssertEqual(gemHistogram[1], 100)
        XCTAssertEqual(gemHistogram[2], 100)

        // UI string must stay tied to the table (regression pin for MetaScreens).
        XCTAssertEqual(line, CrateLoot.oddsDisplayLine)
    }
}
