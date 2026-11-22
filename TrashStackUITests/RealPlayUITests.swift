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
        Thread.sleep(forTimeInterval: 0.9)

        let frame = board.frame
        let drop = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(
                dx: frame.minX + frame.width * 0.10,
                dy: frame.minY + frame.height * 0.78
            ))

        // Visible drag from tray → board (SwiftUI DragGesture / camera).
        let origin = tray0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.25, thenDragTo: drop)
        Thread.sleep(forTimeInterval: 0.45)

        // Commit via floor seat (real placeAtBoard) if the drag only previewed.
        let win = app.otherElements["levelWinOverlay"].firstMatch
        if !win.exists {
            tray0.tap()
            Thread.sleep(forTimeInterval: 0.25)
            let floor0 = app.buttons["boardFloor0"].firstMatch
            if floor0.waitForExistence(timeout: 3), floor0.isHittable {
                // Second beat on camera: drag tray → floor seat, then tap to lock.
                let floorCoord = floor0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                origin.press(forDuration: 0.2, thenDragTo: floorCoord)
                Thread.sleep(forTimeInterval: 0.2)
                if !win.exists { floor0.tap() }
            } else {
                // SpriteKit path: select tray, drag across the board onto col 0 floor.
                let mid = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
                mid.press(forDuration: 0.15, thenDragTo: drop)
                Thread.sleep(forTimeInterval: 0.2)
                drop.tap()
            }
        }

        XCTAssertTrue(
            win.waitForExistence(timeout: 22),
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
