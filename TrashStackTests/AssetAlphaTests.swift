// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
import UIKit
import GameCore
@testable import GameRender

/// Fails if raccoon (or other keyed) art still has opaque checkerboard corners.
final class AssetAlphaTests: XCTestCase {
    func testRaccoonCornersAreTransparent() {
        for name in ["RaccoonIdle", "RaccoonCheer", "RaccoonPanic"] {
            guard let img = JunkTextureLoader.image(named: name),
                  let cg = img.cgImage else {
                XCTFail("Missing raccoon art \(name)")
                continue
            }
            let w = cg.width
            let h = cg.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: &data,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                XCTFail("No context for \(name)")
                continue
            }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

            var transparent = 0
            for i in stride(from: 3, to: data.count, by: 4) {
                if data[i] == 0 { transparent += 1 }
            }
            XCTAssertGreaterThan(transparent, 1000, "\(name) must have true alpha (transparent > 0)")

            let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
            for (x, y) in corners {
                let a = data[(y * w + x) * 4 + 3]
                XCTAssertEqual(a, 0, "\(name) corner (\(x),\(y)) must be transparent, got alpha \(a)")
            }

            // No mid-gray opaque checker in a 16×16 corner block.
            for (x0, y0) in [(0, 0), (w - 16, 0), (0, h - 16), (w - 16, h - 16)] {
                for dy in 0..<16 {
                    for dx in 0..<16 {
                        let x = x0 + dx
                        let y = y0 + dy
                        let i = (y * w + x) * 4
                        let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2]), a = Int(data[i + 3])
                        if a > 200, abs(r - g) < 12, abs(g - b) < 12, r > 60, r < 210 {
                            XCTFail("\(name) has opaque mid-gray checker at (\(x),\(y))")
                            return
                        }
                    }
                }
            }

            // Interior of the silhouette (eroded core) must be ≥ 85% opaque — catches luminance-key ghosts.
            var silhouette = 0
            var coreOpaque = 0
            let margin = max(8, min(w, h) / 16)
            for y in margin..<(h - margin) {
                for x in margin..<(w - margin) {
                    let a = Int(data[(y * w + x) * 4 + 3])
                    // Treat any non-trivial coverage as silhouette for the eroded core sample.
                    if a > 20 {
                        silhouette += 1
                        if a >= 250 { coreOpaque += 1 }
                    }
                }
            }
            XCTAssertGreaterThan(silhouette, 1000, "\(name) silhouette too thin")
            let ratio = Double(coreOpaque) / Double(max(1, silhouette))
            XCTAssertGreaterThanOrEqual(ratio, 0.85, "\(name) interior opacity \(ratio) < 0.85 (luminance-key ghost?)")
        }
    }

    func testJunkSilhouettesHaveCornerAlpha() {
        for def in JunkCatalog.all {
            guard let img = JunkTextureLoader.image(named: def.textureName),
                  let cg = img.cgImage else {
                XCTFail("Missing junk \(def.textureName)")
                continue
            }
            let w = cg.width
            let h = cg.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(
                data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
            for (x, y) in corners {
                XCTAssertEqual(data[(y * w + x) * 4 + 3], 0, "\(def.textureName) corner must be transparent")
            }
        }
    }
}
