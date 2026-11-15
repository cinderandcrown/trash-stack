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

    public static func image(named name: String) -> UIImage? {
        if let img = imageFromModule(named: name) { return img }
        if let img = UIImage(named: name) { return img }
        for bundle in candidateBundles() {
            if let img = UIImage(named: name, in: bundle, compatibleWith: nil) {
                return img
            }
            for sub in ["Junk", "HUD", "Resources/Junk", "Resources/HUD"] {
                if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: sub),
                   let img = UIImage(contentsOfFile: url.path) {
                    return img
                }
            }
            if let url = bundle.url(forResource: name, withExtension: "png"),
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
        let bundle = Bundle.module
        // SPM `.copy("Resources")` may keep or strip the Resources/ prefix — try both.
        let subs = ["Junk", "HUD", "Resources/Junk", "Resources/HUD", "Resources"]
        for sub in subs {
            if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: sub),
               let img = UIImage(contentsOfFile: url.path) {
                return img
            }
        }
        if let url = bundle.url(forResource: name, withExtension: "png"),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        return nil
    }

    public static func candidateBundles() -> [Bundle] {
        var out: [Bundle] = [Bundle.module]
        var seen = Set<ObjectIdentifier>([ObjectIdentifier(Bundle.module)])
        func add(_ b: Bundle?) {
            guard let b else { return }
            let id = ObjectIdentifier(b)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            out.append(b)
        }
        add(Bundle.main)
        add(Bundle(identifier: appBundleId))
        for b in Bundle.allBundles {
            if b.bundleIdentifier?.contains("trashstack") == true
                || b.bundleIdentifier?.contains("GameRender") == true
                || b.bundlePath.hasSuffix(".app")
                || b.bundlePath.contains("GameRender") {
                add(b)
            }
        }
        return out
    }
}
#endif
