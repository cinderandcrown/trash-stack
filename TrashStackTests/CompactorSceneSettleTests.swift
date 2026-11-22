// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
import SpriteKit
import UIKit
import GameCore
@testable import GameRender

/// Drives the real CompactorScene (not just GameCore) through a clear and checks sprite seats.
final class CompactorSceneSettleTests: XCTestCase {
    func testClearAndSettleSpritesMatchModelGrid() async {
        let result = await Self.clearAndSettleOnMain()
        XCTAssertGreaterThan(result.cols, 0)
        XCTAssertTrue(result.noFloats, "model must be packed after clear+settle")
        XCTAssertTrue(result.spritesMatch, "every cell sprite seat/occupancy must match the model grid after settle")
        XCTAssertEqual(result.floorPlastic, .plastic)
        XCTAssertEqual(result.abovePaper, .paper)
        XCTAssertTrue(result.gapEmpty, "gap under packed stack must be empty")
    }

    func testLockOverlapDoesNotPaintStaleSpriteOverResident() async {
        let result = await Self.lockOverlapOnMain()
        XCTAssertEqual(result.resident, .paper)
        XCTAssertTrue(result.spritesMatch)
    }

    @MainActor
    private static func clearAndSettleOnMain() -> (
        cols: Int,
        noFloats: Bool,
        spritesMatch: Bool,
        floorPlastic: Material?,
        abovePaper: Material?,
        gapEmpty: Bool
    ) {
        let size = CGSize(width: 390, height: 844)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = CompactorScene(size: size)
        view.presentScene(scene)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let cols = scene.engine.state.board.config.cols
        let rows = scene.engine.state.board.config.rows
        scene.engine.paceCascades = true
        scene.engine.enableClassicFallingMode()
        scene.engine.seedBoardForTesting(
            cells: [
                (0, rows - 1, Cell(piece: .can, material: .metal)),
                (1, rows - 1, Cell(piece: .can, material: .metal)),
                (2, rows - 1, Cell(piece: .can, material: .metal)),
                (3, rows - 1, Cell(piece: .can, material: .metal)),
                // Stack above the match — must pack onto the floor in the sprites (not a 4+ group).
                (0, rows - 3, Cell(piece: .tire, material: .plastic)),
                (0, rows - 5, Cell(piece: .plank, material: .paper)),
                (1, rows - 3, Cell(piece: .bottle, material: .glass)),
            ],
            active: ActivePiece(id: .bottle, x: 5, y: 0)
        )
        scene.engine.hardDrop()
        scene.testDriveClearAndSettle()

        return (
            cols: cols,
            noFloats: scene.engine.boardHasNoFloatingTiles(),
            spritesMatch: scene.assertSpritesMatchModel(),
            floorPlastic: scene.engine.state.board[0, rows - 1]?.material,
            abovePaper: scene.engine.state.board[0, rows - 2]?.material,
            gapEmpty: scene.engine.state.board[0, rows - 3] == nil
        )
    }

    @MainActor
    private static func lockOverlapOnMain() -> (resident: Material?, spritesMatch: Bool) {
        let size = CGSize(width: 390, height: 844)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = CompactorScene(size: size)
        view.presentScene(scene)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let rows = scene.engine.state.board.config.rows
        scene.engine.paceCascades = true
        scene.engine.seedBoardForTesting(
            cells: [
                (4, rows - 1, Cell(piece: .plank, material: .paper)),
            ],
            active: ActivePiece(id: .can, x: 4, y: rows - 1)
        )
        scene.engine.lock()
        scene.render(immediate: true)

        return (
            resident: scene.engine.state.board[4, rows - 1]?.material,
            spritesMatch: scene.assertSpritesMatchModel()
        )
    }
}
