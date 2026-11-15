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
            XCTAssertNotNil(image, "Missing image for junk piece '\(name)' — not in Assets.xcassets or Resources/Junk")
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
            // Must not be SpriteKit's empty/zero placeholder.
            XCTAssertFalse(texture.size() == .zero, "Junk '\(name)' resolved to empty texture")
        }
    }

    func testHudAndBoardArtPresent() {
        for name in ["DumpsterFrame", "RaccoonIdle", "RaccoonCheer", "RaccoonPanic", "MagnetIcon", "AlleyBackground"] {
            XCTAssertNotNil(JunkTextureLoader.image(named: name), "Missing UI art '\(name)'")
        }
    }

    func testAppBundleExposesJunkLooseFiles() {
        // Belt-and-suspenders: Resources/Junk/*.png must ship in the host app.
        let bundles = JunkTextureLoader.candidateBundles()
        XCTAssertFalse(bundles.isEmpty, "No candidate bundles for Trash Stack assets")
        for name in JunkID.allCases.map(\.rawValue) {
            let found = bundles.contains { bundle in
                bundle.url(forResource: name, withExtension: "png", subdirectory: "Junk") != nil
                    || bundle.url(forResource: name, withExtension: "png") != nil
                    || UIImage(named: name, in: bundle, compatibleWith: nil) != nil
            }
            XCTAssertTrue(found, "Junk '\(name)' missing from app/test bundles (\(bundles.map(\.bundlePath)))")
        }
    }
}
