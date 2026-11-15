// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if canImport(UIKit)
import Foundation
import UIKit
import SpriteKit

/// Resolves junk / HUD art without SpriteKit's red-X placeholder path.
/// Prefers asset-catalog `UIImage(named:)`, then loose `Junk/*.png` in the app bundle.
public enum JunkTextureLoader {
    public static let appBundleId = "com.cinderandcrown.trashstack"

    public static func image(named name: String) -> UIImage? {
        if let img = UIImage(named: name) { return img }
        for bundle in candidateBundles() {
            if let img = UIImage(named: name, in: bundle, compatibleWith: nil) {
                return img
            }
            if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Junk")
                ?? bundle.url(forResource: name, withExtension: "png"),
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

    public static func candidateBundles() -> [Bundle] {
        var out: [Bundle] = []
        var seen = Set<ObjectIdentifier>()
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
            if b.bundleIdentifier?.contains("trashstack") == true || b.bundlePath.hasSuffix(".app") {
                add(b)
            }
        }
        return out
    }
}
#endif
