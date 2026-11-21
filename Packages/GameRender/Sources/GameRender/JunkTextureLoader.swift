// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if canImport(UIKit)
import Foundation
import UIKit
import SpriteKit

/// Resolves junk / HUD art without SpriteKit's red-X placeholder path.
/// Prefer GameRender package resources (`Bundle.module`) so CI unit tests and the
/// SpriteKit scene share one reliable copy of every playable texture.
public enum JunkTextureLoader {
    public static let appBundleId = "com.cinderandcrown.trashstack"

    /// Legacy atlas keys → files that match the material look map.
    /// Banana / bentPipe / fridge swirl-chevron leftovers always resolve to steel `can`.
    private static let aliases: [String: String] = [
        "tube": "glass",
        "scrap": "plank",
        "bag": "tire",
        "box": "crate",
        "bottle": "glass",
        // Keep plank on plank art — cardboard aliases looked like fridge chevrons.
        "pipe": "plastic",
        "crate": "pizza",
        "banana": "can",
        "bentPipe": "can",
        "fridge": "can",
    ]

    /// Keys that must never appear on a playable tile.
    private static let banned: Set<String> = ["banana", "bentPipe", "fridge"]

    public static func resolveName(_ name: String) -> String {
        let aliased = aliases[name] ?? name
        if banned.contains(aliased) { return "can" }
        if banned.contains(name) { return "can" }
        return aliased
    }

    public static func image(named name: String) -> UIImage? {
        let resolved = resolveName(name)
        if let img = imageFromModule(named: resolved) { return img }
        if resolved != name, let img = imageFromModule(named: name) { return img }
        if let img = UIImage(named: resolved) { return img }
        if let img = UIImage(named: name) { return img }
        for bundle in candidateBundles() {
            if let img = UIImage(named: resolved, in: bundle, compatibleWith: nil) {
                return img
            }
            for sub in ["Junk", "HUD", "UI", "Resources/Junk", "Resources/HUD", "Resources/UI"] {
                if let url = bundle.url(forResource: resolved, withExtension: "png", subdirectory: sub),
                   let img = UIImage(contentsOfFile: url.path) {
                    return img
                }
            }
            if let url = bundle.url(forResource: resolved, withExtension: "png"),
               let img = UIImage(contentsOfFile: url.path) {
                return img
            }
        }
        return nil
    }

    public static func texture(named name: String) -> SKTexture? {
        guard let image = image(named: name) else { return nil }
        let t = SKTexture(image: image)
        guard t.size().width >= 4, t.size().height >= 4 else { return nil }
        t.filteringMode = .linear
        return t
    }

    /// Package-local PNGs under Resources/Junk and Resources/HUD.
    public static func imageFromModule(named name: String) -> UIImage? {
        let resolved = resolveName(name)
        let bundle = Bundle.module
        let subs = ["Junk", "HUD", "Resources/Junk", "Resources/HUD", "Resources"]
        for sub in subs {
            if let url = bundle.url(forResource: resolved, withExtension: "png", subdirectory: sub),
               let img = UIImage(contentsOfFile: url.path) {
                return img
            }
        }
        if let url = bundle.url(forResource: resolved, withExtension: "png"),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        return nil
    }

    /// Keep this tiny — scanning `Bundle.allBundles` hung CI unit tests for 25+ minutes.
    public static func candidateBundles() -> [Bundle] {
        var out: [Bundle] = [Bundle.module]
        if Bundle.main !== Bundle.module {
            out.append(Bundle.main)
        }
        if let app = Bundle(identifier: appBundleId), app !== Bundle.main, app !== Bundle.module {
            out.append(app)
        }
        return out
    }
}
#endif
