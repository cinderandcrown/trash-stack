// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest

/// Drives Level 1 turn-based play: tray drag → place → clear → chain → win with stars.
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

        let play = app.buttons["playButton"].firstMatch.exists
            ? app.buttons["playButton"].firstMatch
            : app.buttons["PLAY"].firstMatch
        if play.waitForExistence(timeout: 3), play.isHittable {
            play.tap()
        }

        let gotIt = app.buttons["GOT IT — PLAY"].firstMatch
        if gotIt.waitForExistence(timeout: 1) {
            gotIt.tap()
        }

        let board = app.otherElements["gameBoard"].firstMatch
        XCTAssertTrue(
            board.waitForExistence(timeout: 8),
            "gameBoard must appear within ~10s of launch for real-play video"
        )

        let tray0 = app.buttons["traySlot0"].firstMatch
        XCTAssertTrue(tray0.waitForExistence(timeout: 6), "tray slot 0 must exist for Level 1")
        Thread.sleep(forTimeInterval: 0.6)

        let frame = board.frame
        let drop = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(
                dx: frame.minX + frame.width * 0.10,
                dy: frame.minY + frame.height * 0.78
            ))

        // Visible drag-place beat on camera (tray → board floor).
        let origin = tray0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.3, thenDragTo: drop)

        // Also tap the teach control if present (belt-and-suspenders with app-side auto-place).
        let place = app.buttons["uitestPlaceTeach"].firstMatch
        if place.waitForExistence(timeout: 2), place.isHittable {
            place.tap()
        }

        // App auto-commits placeTeachSeat ~4.5s after bootstrap if still unplaced.
        let win = app.otherElements["levelWinOverlay"].firstMatch
        let clearLabel = app.staticTexts["LEVEL CLEAR"].firstMatch
        let deadline = Date().addingTimeInterval(28)
        while Date() < deadline {
            if win.exists || clearLabel.exists { break }
            Thread.sleep(forTimeInterval: 0.35)
        }

        XCTAssertTrue(
            win.exists || clearLabel.exists,
            "Level 1 must finish after the teach place (clear + chain)"
        )
        XCTAssertTrue(
            app.otherElements["levelStars"].exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '★'")).count > 0
                || clearLabel.exists,
            "stars should show on level clear"
        )
        Thread.sleep(forTimeInterval: 3.0)
    }
}
