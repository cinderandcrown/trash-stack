// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
import UIKit
import SpriteKit
import GameCore
@testable import GameRender

/// Fails CI if any junk piece would draw SpriteKit's red-X missing-texture placeholder.
final class JunkTextureTests: XCTestCase {
    func testEveryJunkPieceHasBundleImage() {
        for id in JunkID.allCases {
            let name = id.rawValue
            let image = JunkTextureLoader.image(named: name)
            XCTAssertNotNil(image, "Missing image for junk piece '\(name)' — expected in GameRender Resources/Junk")
            guard let image else { continue }
            XCTAssertGreaterThan(image.size.width, 8, "Junk '\(name)' image too small")
            XCTAssertGreaterThan(image.size.height, 8, "Junk '\(name)' image too small")
        }
    }

    func testSKTextureFromUIImageIsNotPlaceholder() {
        let names = JunkID.allCases.map(\.rawValue)
        XCTAssertEqual(names, CompactorScene.requiredJunkTextureNames)
        for name in names {
            guard let texture = JunkTextureLoader.texture(named: name) else {
                XCTFail("No SKTexture for \(name)")
                continue
            }
            XCTAssertGreaterThan(texture.size().width, 8)
            XCTAssertGreaterThan(texture.size().height, 8)
            XCTAssertFalse(texture.size() == .zero, "Junk '\(name)' resolved to empty texture")
        }
    }

    func testHudAndBoardArtPresent() {
        for name in ["DumpsterFrame", "RaccoonIdle", "RaccoonCheer", "RaccoonPanic", "MagnetIcon"] {
            XCTAssertNotNil(
                JunkTextureLoader.image(named: name),
                "Missing HUD art '\(name)' — expected in GameRender Resources/HUD"
            )
        }
    }

    func testModuleBundleExposesJunkFiles() {
        for name in JunkID.allCases.map(\.rawValue) {
            // imageFromModule reads GameRender's Bundle.module (not the test bundle).
            XCTAssertNotNil(
                JunkTextureLoader.imageFromModule(named: name),
                "GameRender Bundle.module missing junk '\(name)'"
            )
        }
    }
}
