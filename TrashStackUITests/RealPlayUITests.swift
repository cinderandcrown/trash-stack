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

        let tray0 = app.otherElements["traySlot0"].firstMatch.exists
            ? app.otherElements["traySlot0"].firstMatch
            : app.buttons["traySlot0"].firstMatch
        XCTAssertTrue(tray0.waitForExistence(timeout: 6), "tray slot 0 must exist for Level 1")

        // Give the board a moment to lay out floor accessibility seats + scene size.
        Thread.sleep(forTimeInterval: 0.8)

        let frame = board.frame
        // Level 1 teach seat: column 0 floor — left of the three metal tiles.
        // Stay above the neon lip pad (~bottom 20%) so boardCell resolves.
        let drop = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(
                dx: frame.minX + frame.width * 0.10,
                dy: frame.minY + frame.height * 0.70
            ))

        // Drag from tray → board so SwiftUI DragGesture selects + places.
        let origin = tray0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.2, thenDragTo: drop)

        // If the drag only previewed, tap the floor seat / coordinate to lock.
        Thread.sleep(forTimeInterval: 0.5)
        let floor0 = app.otherElements["boardFloor0"].firstMatch
        if floor0.exists {
            // Accessibility seat is non-hittable; use its frame center via coordinate.
            let f = floor0.frame
            if f.width > 2, f.height > 2 {
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: f.midX, dy: f.midY))
                    .tap()
            } else {
                drop.tap()
            }
        } else {
            // Tap tray then board (SpriteKit place path).
            tray0.tap()
            Thread.sleep(forTimeInterval: 0.25)
            let mid = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            mid.press(forDuration: 0.12, thenDragTo: drop)
        }

        // Wait for metal clear → plastic chain → level win with stars.
        let win = app.otherElements["levelWinOverlay"].firstMatch
        XCTAssertTrue(
            win.waitForExistence(timeout: 20),
            "Level 1 must finish after the teach place (clear + chain)"
        )
        XCTAssertTrue(
            app.otherElements["levelStars"].exists
                || app.staticTexts["LEVEL CLEAR"].exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '★'")).count > 0,
            "stars should show on level clear"
        )
        // Hold so muxed real-play captures stars on camera.
        Thread.sleep(forTimeInterval: 3.0)
    }
}
