// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
import SpriteKit
import Services
import GameRender

/// Warm textures + audio during the publisher ident so PLAY → first board is fast.
enum AssetPreloader {
    private static var started = false

    @MainActor
    static func preloadDuringIdent() {
        guard !started else { return }
        started = true
        Task.detached(priority: .userInitiated) {
            let names = CompactorScene.requiredJunkTextureNames + [
                "AlleyBackground", "DumpsterFrame",
                "RaccoonIdle", "RaccoonCheer", "RaccoonPanic",
                "SparkGold", "SparkTeal", "SparkMagenta",
                "DebrisMetal", "DebrisNeon", "MagnetIcon",
            ]
            for name in names {
                if let tex = JunkTextureLoader.texture(named: name) {
                    tex.preload {}
                } else {
                    SKTexture(imageNamed: name).preload {}
                }
            }
            await MainActor.run {
                AudioService.shared.prepare()
                AudioService.shared.preloadCommonSFX()
            }
        }
    }
}
