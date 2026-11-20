// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import GameCore

final class TrashTalkTests: XCTestCase {
    func testJunkRowFormula() {
        XCTAssertEqual(TrashTalkRules.junkRows(clears: 1, combo: 1), 0)
        XCTAssertEqual(TrashTalkRules.junkRows(clears: 2, combo: 1), 1)
        XCTAssertEqual(TrashTalkRules.junkRows(clears: 3, combo: 1), 2)
        XCTAssertEqual(TrashTalkRules.junkRows(clears: 4, combo: 1), 4)
        XCTAssertEqual(TrashTalkRules.junkRows(clears: 4, combo: 3), 6)
    }

    func testWireRoundTrip() {
        let samples: [TrashTalkWire] = [
            .hello(seed: 0xDEAD_BEEF_CAFE_BABE),
            .lock(pieceIndex: 12, x: 3, y: -2, rot: 1, hard: true),
            .junk(rows: 4),
            .boardDigest(filled: 200, topY: 3),
            .topOut,
            .rematch,
            .ping,
        ]
        for sample in samples {
            let decoded = TrashTalkWire.decode(sample.encode())
            XCTAssertEqual(decoded, sample)
        }
    }

    func testJunkLandsAfterWarning() {
        var eng = GameEngine(seed: 42)
        eng.queueJunk(rows: 2)
        XCTAssertEqual(eng.state.pendingJunkRows, 2)
        _ = eng.tickJunkWarning(dt: 0.5)
        XCTAssertEqual(eng.state.pendingJunkRows, 2)
        _ = eng.drainEvents()
        _ = eng.tickJunkWarning(dt: TrashTalkRules.junkWarningSec)
        let ev = eng.drainEvents()
        XCTAssertTrue(ev.contains { if case .junkLanded(let r) = $0 { return r == 2 }; return false })
        XCTAssertEqual(eng.state.pendingJunkRows, 0)
    }

    func testBotEmitsJunkOrSurvives() {
        var bot = TrashTalkBot(seed: 7, thinkInterval: 0.01)
        var total = 0
        for _ in 0..<200 {
            total += bot.tick(dt: 0.05)
            if bot.engine.state.over { break }
        }
        XCTAssertGreaterThan(bot.engine.lockCount + total, 0)
    }

    func testWeeklySeedStable() {
        let a = WeeklyTournament.seed()
        let b = WeeklyTournament.seed()
        XCTAssertEqual(a, b)
        XCTAssertFalse(WeeklyTournament.weekKey().isEmpty)
    }
}
