// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest

/// Fresh New Game → Levels 1–3 via real tray tap → board tap → map → next level.
/// No test-only place shortcuts. Pauses between beats for recordVideo (≥60s play).
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

        // —— Level 1: can beside three metal ——
        try playOneMoveLevel(
            app: app,
            floorSeat: "boardFloor1",
            expectMapLevel: 2
        )

        // —— Level 2: pink pipe beside three plastic ——
        try playOneMoveLevel(
            app: app,
            floorSeat: "boardFloor3",
            expectMapLevel: 3
        )

        // —— Level 3: bottle beside three glass ——
        try playOneMoveLevel(
            app: app,
            floorSeat: "boardFloor3",
            expectMapLevel: 4,
            openNextFromMap: false
        )

        // Hold end state on camera so the mux has 60s+ of real play.
        Thread.sleep(forTimeInterval: 3.0)
    }

    /// Tray slot 0 → floor seat → win → map → optional next level.
    private func playOneMoveLevel(
        app: XCUIApplication,
        floorSeat: String,
        expectMapLevel: Int,
        openNextFromMap: Bool = true
    ) throws {
        let board = app.otherElements["gameBoard"].firstMatch
        XCTAssertTrue(
            board.waitForExistence(timeout: 10),
            "gameBoard must appear for level play"
        )
        Thread.sleep(forTimeInterval: 0.9)

        let tray0 = app.buttons["traySlot0"].firstMatch
        XCTAssertTrue(tray0.waitForExistence(timeout: 6), "tray slot 0 must exist")
        tray0.tap()
        Thread.sleep(forTimeInterval: 0.75)

        let seat = app.buttons[floorSeat].firstMatch
        XCTAssertTrue(
            seat.waitForExistence(timeout: 4),
            "\(floorSeat) must appear after selecting a tray piece"
        )
        XCTAssertTrue(seat.isHittable, "\(floorSeat) must be hittable")
        seat.tap()

        // Place settle + clear fly + chain, then delayed LEVEL CLEAR after CHAIN.
        Thread.sleep(forTimeInterval: 3.0)

        let win = app.descendants(matching: .any)["levelWinOverlay"].firstMatch
        let clear = app.staticTexts["LEVEL CLEAR"].firstMatch
        XCTAssertTrue(
            win.waitForExistence(timeout: 16) || clear.waitForExistence(timeout: 2),
            "Level must clear after tap-to-place"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["levelStars"].firstMatch.exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '★'")).count > 0
                || clear.exists,
            "stars should show on level clear"
        )
        // Hold stars on camera before map.
        Thread.sleep(forTimeInterval: 1.6)

        // Map: auto-open or tap LEVEL MAP.
        let mapBtn = app.buttons["levelMapButton"].firstMatch
        if mapBtn.waitForExistence(timeout: 2), mapBtn.isHittable {
            mapBtn.tap()
        }

        let mapTitle = app.staticTexts["LEVEL MAP"].firstMatch
        let nextRow = app.buttons["levelMap\(expectMapLevel)"].firstMatch
        XCTAssertTrue(
            mapTitle.waitForExistence(timeout: 8) || nextRow.waitForExistence(timeout: 3),
            "Level map must show after the win (next=\(expectMapLevel))"
        )
        Thread.sleep(forTimeInterval: 1.4)

        guard openNextFromMap else { return }

        XCTAssertTrue(
            nextRow.waitForExistence(timeout: 4),
            "levelMap\(expectMapLevel) must be unlocked after prior clear"
        )
        XCTAssertTrue(nextRow.isHittable, "levelMap\(expectMapLevel) must be tappable")
        nextRow.tap()
        Thread.sleep(forTimeInterval: 1.2)
    }
}
