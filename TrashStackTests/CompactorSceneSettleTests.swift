// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
import SpriteKit
import UIKit
import GameCore
@testable import GameRender

/// Drives the real CompactorScene (not just GameCore) through a clear and checks sprite seats.
final class CompactorSceneSettleTests: XCTestCase {
    func testClearAndSettleSpritesMatchModelGrid() {
        let size = CGSize(width: 390, height: 844)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = CompactorScene(size: size)
        view.presentScene(scene)
        // didMove → rebuild; give the run loop a beat so the scene is live.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(scene.engine.state.board.config.cols == 0)

        let rows = scene.engine.state.board.config.rows
        scene.engine.paceCascades = true
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

        XCTAssertTrue(
            scene.engine.boardHasNoFloatingTiles(),
            "model must be packed after clear+settle"
        )
        XCTAssertTrue(
            scene.assertSpritesMatchModel(),
            "every cell sprite seat/occupancy must match the model grid after settle"
        )
        // Leftmost column: plastic + paper must sit on the floor with no empty gap under them.
        XCTAssertEqual(scene.engine.state.board[0, rows - 1]?.material, .plastic)
        XCTAssertEqual(scene.engine.state.board[0, rows - 2]?.material, .paper)
        XCTAssertNil(scene.engine.state.board[0, rows - 3])
    }

    func testLockOverlapDoesNotPaintStaleSpriteOverResident() {
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

        XCTAssertEqual(scene.engine.state.board[4, rows - 1]?.material, .paper)
        XCTAssertTrue(scene.assertSpritesMatchModel())
    }
}
