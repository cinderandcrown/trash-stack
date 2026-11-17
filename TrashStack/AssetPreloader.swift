// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
import SpriteKit
import Services
import GameRender

/// Warm textures + audio during the publisher ident so PLAY → first board is fast.
@MainActor
enum AssetPreloader {
    private static var started = false

    static func preloadDuringIdent() {
        guard !started else { return }
        started = true
        let names = CompactorScene.requiredJunkTextureNames + [
            "AlleyBackground", "DumpsterFrame",
            "RaccoonIdle", "RaccoonCheer", "RaccoonPanic",
            "SparkGold", "SparkTeal", "SparkMagenta",
            "DebrisMetal", "DebrisNeon", "MagnetIcon",
        ]
        // Decode off the critical path without SKTexture.preload(_:) (Swift 6 warns on the callback form).
        Task(priority: .userInitiated) { @MainActor in
            for name in names {
                _ = JunkTextureLoader.texture(named: name) ?? SKTexture(imageNamed: name)
            }
            AudioService.shared.prepare()
            AudioService.shared.preloadCommonSFX()
        }
    }
}
