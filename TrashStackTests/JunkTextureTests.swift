// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
import UIKit
import SpriteKit
import GameCore
@testable import GameRender

/// Fails CI if any junk item would draw SpriteKit's red-X missing-texture placeholder.
final class JunkTextureTests: XCTestCase {
    func testEveryJunkPieceHasBundleImage() {
        for def in JunkCatalog.all {
            let name = def.textureName
            let image = JunkTextureLoader.image(named: name)
            XCTAssertNotNil(image, "Missing image for junk '\(def.id.rawValue)' texture '\(name)'")
            guard let image else { continue }
            XCTAssertGreaterThan(image.size.width, 8)
            XCTAssertGreaterThan(image.size.height, 8)
        }
    }

    func testSKTextureFromUIImageIsNotPlaceholder() {
        let names = JunkCatalog.all.map(\.textureName)
        XCTAssertEqual(names, CompactorScene.requiredJunkTextureNames)
        for name in names {
            guard let texture = JunkTextureLoader.texture(named: name) else {
                XCTFail("No SKTexture for \(name)")
                continue
            }
            XCTAssertGreaterThan(texture.size().width, 8)
            XCTAssertGreaterThan(texture.size().height, 8)
        }
    }

    func testHudAndBoardArtPresent() {
        for name in ["DumpsterFrame", "RaccoonIdle", "RaccoonCheer", "RaccoonPanic", "MagnetIcon", "SparkTeal"] {
            XCTAssertNotNil(
                JunkTextureLoader.image(named: name),
                "Missing HUD art '\(name)'"
            )
        }
    }

    func testModuleBundleExposesJunkFiles() {
        for def in JunkCatalog.all {
            XCTAssertNotNil(
                JunkTextureLoader.imageFromModule(named: def.textureName),
                "GameRender Bundle.module missing '\(def.textureName)'"
            )
        }
    }
}
