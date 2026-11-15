// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
import GameCore

final class SmokeTests: XCTestCase {
    func testBoardIdentity() {
        XCTAssertEqual(BoardConfig.dumpster.cols, 8)
        XCTAssertEqual(BoardConfig.dumpster.visibleRows, 14)
    }

    func testEconomyResourceLoads() throws {
        let eco = try ConfigLoader.economy()
        XCTAssertEqual(eco.compliance.maxAgeRating, "12+")
        try EconomyMath.assertOfferCaps(eco.oneTimeOffer)
    }

    func testSeasonShape() throws {
        let season = try ConfigLoader.activeSeason()
        try EconomyMath.assertSeasonShape(season)
    }

    func testDailyDumpsterShareAndModes() {
        let seed = DailyDumpster.seed()
        XCTAssertGreaterThan(seed, 0)
        let card = DailyDumpster.shareCard(
            dayKey: DailyDumpster.dayKey(),
            score: 1200,
            stars: 2,
            materialGrid: [[.metal, .glass, nil, .plastic, .paper, .metal, .glass, .plastic]]
        )
        XCTAssertTrue(card.contains("Daily Dumpster"))
        XCTAssertTrue(card.contains("★★☆") || card.contains("★"))
        XCTAssertEqual(PlayMode.allCases, [.shift, .endless, .daily])
        XCTAssertFalse(ShiftCatalog.levels.isEmpty)
        XCTAssertEqual(StreakRewards.scrap(forDay: 3), 34)
    }
}
