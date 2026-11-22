// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest

/// Level 1 via the same tap-to-place path players use: tray tap → ghost → board tap.
/// Pauses between beats so recordVideo captures place / clear / chain / win / map.
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
        // Let the board + tray settle on camera.
        Thread.sleep(forTimeInterval: 1.2)

        let tray0 = app.buttons["traySlot0"].firstMatch
        XCTAssertTrue(tray0.waitForExistence(timeout: 6), "tray slot 0 must exist")

        // Beat 1 — select tray piece (lift + glow + ghost).
        tray0.tap()
        Thread.sleep(forTimeInterval: 0.85)

        // Beat 2 — tap empty floor seat beside the three metal tiles (col 1).
        let floor1 = app.buttons["boardFloor1"].firstMatch
        XCTAssertTrue(
            floor1.waitForExistence(timeout: 4),
            "boardFloor1 tap seat must appear after selecting a tray piece"
        )
        XCTAssertTrue(floor1.isHittable, "boardFloor1 must be hittable for tap-to-place")
        floor1.tap()

        // Beat 3 — place pop + metal clear fly-to-goal (~0.3s) + plastic chain (~0.3s).
        Thread.sleep(forTimeInterval: 1.4)

        // Beat 4 — level win + stars.
        let win = app.otherElements["levelWinOverlay"].firstMatch
        let clear = app.staticTexts["LEVEL CLEAR"].firstMatch
        XCTAssertTrue(
            win.waitForExistence(timeout: 16) || clear.waitForExistence(timeout: 2),
            "Level 1 must win after tap-to-place (metal clear + plastic chain)"
        )
        XCTAssertTrue(
            app.otherElements["levelStars"].exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '★'")).count > 0
                || clear.exists,
            "stars should show on level clear"
        )
        // Hold stars on camera, then auto-map or tap LEVEL MAP.
        Thread.sleep(forTimeInterval: 1.8)

        let mapBtn = app.buttons["levelMapButton"].firstMatch
        if mapBtn.waitForExistence(timeout: 1), mapBtn.isHittable {
            mapBtn.tap()
        }

        // Beat 5 — level map visible.
        let mapTitle = app.staticTexts["LEVEL MAP"].firstMatch
        let mapL1 = app.buttons["levelMap1"].firstMatch
        XCTAssertTrue(
            mapTitle.waitForExistence(timeout: 6) || mapL1.waitForExistence(timeout: 2),
            "Level map must show after the win"
        )
        Thread.sleep(forTimeInterval: 2.2)
    }
}
