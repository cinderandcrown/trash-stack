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

        // Prefer accessibility id; fall back to visible label (NeonButton).
        let play = app.buttons["playButton"].firstMatch.exists
            ? app.buttons["playButton"].firstMatch
            : app.buttons["PLAY"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "PLAY button missing on title")
        XCTAssertTrue(play.isHittable, "PLAY button not hittable")
        play.tap()

        let gotIt = app.buttons["GOT IT — PLAY"].firstMatch
        if gotIt.waitForExistence(timeout: 2) {
            gotIt.tap()
        }

        let board = app.otherElements["gameBoard"].firstMatch
        _ = board.waitForExistence(timeout: 10)

        // ~60s of steady inputs after PLAY (natural GO may end early).
        let deadline = Date().addingTimeInterval(62)
        var gestures = 0
        var sawGameOver = false

        while Date() < deadline {
            if gestures % 4 == 0, isGameOverVisible(in: app) {
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

            // Bias toward stacking so gravity / land / clear / overflow show up.
            switch gestures % 9 {
            case 0, 1, 2:
                mid.press(forDuration: 0.01, thenDragTo: left)
            case 3:
                mid.tap()
            case 4, 5:
                top.press(forDuration: 0.01, thenDragTo: bottom)
            case 6:
                mid.press(forDuration: 0.01, thenDragTo: right)
                mid.tap()
            default:
                top.press(forDuration: 0.01, thenDragTo: bottom)
            }
            gestures += 1
            Thread.sleep(forTimeInterval: 0.07)
        }

        if !sawGameOver {
            sawGameOver = isGameOverVisible(in: app)
        }
        if sawGameOver {
            Thread.sleep(forTimeInterval: 2.0)
            let score = app.staticTexts["gameOverScore"].firstMatch
            if score.exists {
                let raw = score.label.replacingOccurrences(of: ",", with: "")
                if let value = Int(raw) {
                    XCTAssertGreaterThan(value, 0, "Game-over must show true final score, not 0")
                }
            }
        }

        // Printed into the xcodebuild log so CI proves PLAY + board input ran.
        print("RealPlay gestures=\(gestures) gameOver=\(sawGameOver)")

        if sawGameOver {
            XCTAssertGreaterThan(gestures, 8, "Expected some real-play before game over, got \(gestures)")
        } else {
            XCTAssertGreaterThan(gestures, 30, "Expected ~60s of real-play gestures, got \(gestures)")
        }
    }

    private func isGameOverVisible(in app: XCUIApplication) -> Bool {
        app.staticTexts["NEW BEST"].exists
            || app.staticTexts["BIN FULL"].exists
            || app.staticTexts["SO CLOSE"].exists
            || app.otherElements["Game over"].exists
    }
}
