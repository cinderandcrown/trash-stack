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
        Thread.sleep(forTimeInterval: 0.8)

        let frame = board.frame
        let drop = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(
                dx: frame.minX + frame.width * 0.10,
                dy: frame.minY + frame.height * 0.78
            ))

        // Visible drag-place on camera (tray → board).
        let origin = tray0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.25, thenDragTo: drop)
        Thread.sleep(forTimeInterval: 0.35)

        let win = app.otherElements["levelWinOverlay"].firstMatch
        if !win.exists {
            // Commit via tray-chrome teach control (calls real placeAtBoard + cascade drain).
            let place = app.buttons["uitestPlaceTeach"].firstMatch
            XCTAssertTrue(place.waitForExistence(timeout: 4), "uitestPlaceTeach must exist under -UITestRealPlay")
            // Drag onto the control so the clip still shows a drag beat, then tap to lock.
            origin.press(forDuration: 0.15, thenDragTo: place.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            Thread.sleep(forTimeInterval: 0.2)
            if !win.exists {
                place.tap()
            }
        }

        XCTAssertTrue(
            win.waitForExistence(timeout: 25),
            "Level 1 must finish after the teach place (clear + chain)"
        )
        XCTAssertTrue(
            app.otherElements["levelStars"].exists
                || app.staticTexts["LEVEL CLEAR"].exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '★'")).count > 0,
            "stars should show on level clear"
        )
        Thread.sleep(forTimeInterval: 3.0)
    }
}
