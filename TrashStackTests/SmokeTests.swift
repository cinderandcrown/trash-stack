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
}
