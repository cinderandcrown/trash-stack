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
            let image = UIImage(named: name)
            XCTAssertNotNil(image, "Missing UIImage for junk piece '\(name)' — asset not in app bundle")
            guard let image else { continue }
            XCTAssertGreaterThan(image.size.width, 8, "Junk '\(name)' image too small")
            XCTAssertGreaterThan(image.size.height, 8, "Junk '\(name)' image too small")
        }
    }

    func testSKTextureFromUIImageIsNotPlaceholder() {
        for name in CompactorScene.requiredJunkTextureNames {
            guard let image = UIImage(named: name) else {
                XCTFail("No UIImage named \(name)")
                continue
            }
            let texture = SKTexture(image: image)
            XCTAssertGreaterThan(texture.size().width, 8)
            XCTAssertGreaterThan(texture.size().height, 8)
            // Placeholder red-X from SKTexture(imageNamed:) is typically square ~128;
            // our art is also 128 — so additionally assert the UIImage path succeeded
            // (UIImage(named:) returns nil on miss; SKTexture(imageNamed:) does not).
            let viaNamed = SKTexture(imageNamed: name)
            // If UIImage loaded, imageNamed should match a real asset size (not 0).
            XCTAssertGreaterThan(viaNamed.size().width, 1, "SKTexture(imageNamed: \(name)) unresolved")
        }
    }

    func testHudAndBoardArtPresent() {
        for name in ["DumpsterFrame", "RaccoonIdle", "RaccoonCheer", "RaccoonPanic", "MagnetIcon", "AlleyBackground"] {
            XCTAssertNotNil(UIImage(named: name), "Missing UI art '\(name)'")
        }
    }
}
