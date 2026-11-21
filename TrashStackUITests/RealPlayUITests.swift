// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest

/// Drives a fresh New Game with real board gestures while CI records the simulator.
/// No `-trashStackShot`, no seeded boards, no demo/autoplay scene swaps.
final class RealPlayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRealPlaySession() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-trashStackSkipAds",
            "-trashStackSkipIdent",
            "-UITestRealPlay",
        ]
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launch()

        // Title → PLAY (harness forces title so this is a visible New Game).
        let play = app.buttons["PLAY"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 25), "PLAY button missing on title")
        // Hold on title so recordVideo (started once the app is up) captures the brand frame.
        Thread.sleep(forTimeInterval: 1.2)
        play.tap()

        let gotIt = app.buttons["GOT IT — PLAY"].firstMatch
        if gotIt.waitForExistence(timeout: 2) {
            gotIt.tap()
        }

        // Prefer the SKView accessibility id; fall back to screen mid-board.
        let board = app.otherElements["gameBoard"].firstMatch
        _ = board.waitForExistence(timeout: 8)

        let deadline = Date().addingTimeInterval(82)
        var gestures = 0
        var sawGameOver = false

        while Date() < deadline {
            if app.staticTexts["NEW BEST"].exists
                || app.staticTexts["SO CLOSE"].exists
                || app.staticTexts["BIN FULL"].exists
                || app.otherElements["Game over"].exists {
                sawGameOver = true
                break
            }

            let frame: CGRect
            if board.exists {
                frame = board.frame
            } else {
                let w = app.frame.width
                let h = app.frame.height
                frame = CGRect(x: w * 0.08, y: h * 0.22, width: w * 0.84, height: h * 0.55)
            }

            let cx = frame.midX
            let cy = frame.midY
            let leftX = frame.minX + frame.width * 0.18
            let rightX = frame.minX + frame.width * 0.82
            let mid = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: cx, dy: cy))
            let left = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: leftX, dy: cy))
            let right = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: rightX, dy: cy))
            let top = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: cx, dy: frame.minY + frame.height * 0.18))
            let bottom = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: cx, dy: frame.maxY - frame.height * 0.12))

            // Bias toward stacking so the bin overflows inside ~60–90s while still
            // rotating / dropping so gravity, landings, and recycles are visible.
            switch gestures % 9 {
            case 0, 1, 2:
                mid.press(forDuration: 0.04, thenDragTo: left)
            case 3:
                mid.tap() // rotate
            case 4, 5:
                top.press(forDuration: 0.04, thenDragTo: bottom) // hard drop
            case 6:
                mid.press(forDuration: 0.04, thenDragTo: right)
                mid.tap()
            default:
                top.press(forDuration: 0.04, thenDragTo: bottom)
            }
            gestures += 1
            Thread.sleep(forTimeInterval: 0.28)
        }

        XCTAssertGreaterThan(gestures, 25, "Expected sustained real-play gestures, got \(gestures)")
        // Prefer natural overflow; if still alive the recording still shows live play.
        if !sawGameOver {
            _ = app.staticTexts["NEW BEST"].waitForExistence(timeout: 3)
                || app.staticTexts["BIN FULL"].waitForExistence(timeout: 1)
                || app.staticTexts["SO CLOSE"].waitForExistence(timeout: 1)
        }
        // Hold a beat so recordVideo captures the GO overlay score.
        if app.staticTexts["NEW BEST"].exists
            || app.staticTexts["BIN FULL"].exists
            || app.staticTexts["SO CLOSE"].exists {
            Thread.sleep(forTimeInterval: 2.5)
            let score = app.staticTexts["gameOverScore"].firstMatch
            if score.exists {
                let raw = score.label.replacingOccurrences(of: ",", with: "")
                if let value = Int(raw) {
                    XCTAssertGreaterThan(value, 0, "Game-over must show true final score, not 0")
                }
            }
        }
    }
}
