// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest

/// Level 1 via the same tap-to-place path players use: tray tap → board cell tap.
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
            "gameBoard must appear for real-play video"
        )

        let tray0 = app.buttons["traySlot0"].firstMatch
        XCTAssertTrue(tray0.waitForExistence(timeout: 6), "tray slot 0 must exist")

        // Player path: tap tray piece → ghost → tap floor seat beside the metal.
        tray0.tap()
        Thread.sleep(forTimeInterval: 0.45)

        let floor0 = app.buttons["boardFloor0"].firstMatch
        XCTAssertTrue(
            floor0.waitForExistence(timeout: 4),
            "boardFloor0 tap seat must appear after selecting a tray piece"
        )
        XCTAssertTrue(floor0.isHittable, "boardFloor0 must be hittable for tap-to-place")
        floor0.tap()

        // Clear → chain → level win (paced cascades need a few beats on camera).
        let win = app.otherElements["levelWinOverlay"].firstMatch
        let clear = app.staticTexts["LEVEL CLEAR"].firstMatch
        XCTAssertTrue(
            win.waitForExistence(timeout: 20) || clear.waitForExistence(timeout: 1),
            "Level 1 must win after tap-to-place (metal clear + plastic chain)"
        )
        XCTAssertTrue(
            app.otherElements["levelStars"].exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '★'")).count > 0
                || clear.exists,
            "stars should show on level clear"
        )
        Thread.sleep(forTimeInterval: 3.0)
    }
}
