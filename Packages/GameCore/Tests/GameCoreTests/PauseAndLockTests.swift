// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import GameCore

final class PauseAndLockTests: XCTestCase {
    func testPauseIsIdempotentAndOnlyResumeClears() {
        var gate = PauseGate()
        XCTAssertFalse(gate.isPaused)
        XCTAssertTrue(gate.pause(as: .user))
        XCTAssertTrue(gate.isPaused)
        // Second pause must not toggle off.
        XCTAssertFalse(gate.pause(as: .resign))
        XCTAssertEqual(gate.reason, .user)
        // Becoming active again is not modeled as auto-resume — only resume().
        XCTAssertTrue(gate.resume())
        XCTAssertFalse(gate.isPaused)
        XCTAssertFalse(gate.resume())
    }

    func testResignAutoPausesOnce() {
        var gate = PauseGate()
        XCTAssertTrue(gate.noteResignActive())
        XCTAssertEqual(gate.reason, .resign)
        XCTAssertFalse(gate.noteResignActive())
        XCTAssertTrue(gate.resume())
    }

    func testGroundedLockWithinHalfSecondWithoutResets() {
        var eng = GameEngine(seed: 99)
        let before = eng.lockCount
        // Drop until grounded without locking via hardDrop.
        var steps = 0
        while !eng.isGrounded(), steps < 80, !eng.state.over {
            _ = eng.softDrop()
            steps += 1
        }
        XCTAssertTrue(eng.isGrounded())
        XCTAssertNotNil(eng.state.active)
        // Mimic scene lock timer: 0.5s grounded → lock (spawn follows, so active may be non-nil).
        _ = eng.drainEvents()
        eng.lock()
        let ev = eng.drainEvents()
        XCTAssertTrue(ev.contains { if case .locked = $0 { return true }; return false })
        XCTAssertEqual(eng.lockCount, before + 1)
    }

    func testLockResetCapForcesSettle() {
        // After max resets, piece must still be lockable (engine still accepts lock).
        var eng = GameEngine(seed: 7)
        let before = eng.lockCount
        while !eng.isGrounded(), !eng.state.over {
            _ = eng.softDrop()
        }
        XCTAssertTrue(eng.isGrounded())
        let maxResets = 15
        var resets = 0
        while resets < maxResets, eng.state.active != nil {
            if eng.tryMove(dx: -1, dy: 0) || eng.tryMove(dx: 1, dy: 0) || eng.tryRotate() {
                resets += 1
            } else {
                break
            }
        }
        // Cap reached or can't move — lock must succeed (spawn may refill active).
        _ = eng.drainEvents()
        eng.lock()
        let ev = eng.drainEvents()
        XCTAssertTrue(ev.contains { if case .locked = $0 { return true }; return false })
        XCTAssertEqual(eng.lockCount, before + 1)
    }

    func testLevelToastFitsBannerBudget() {
        for twist in LevelTwist.allCases {
            XCTAssertLessThanOrEqual(twist.toastTitle.count, 42, twist.toastTitle)
            XCTAssertFalse(twist.toastTitle.contains("…"))
        }
    }
}
