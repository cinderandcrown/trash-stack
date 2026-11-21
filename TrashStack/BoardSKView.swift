// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import SpriteKit
import GameRender

/// Hosts `CompactorScene` in a real `SKView`.
///
/// SwiftUI `SpriteView` + `.clipShape` left a perfect flat grey (RGB 191) rectangle
/// on the iOS 27 simulator while the HUD still updated — Metal never composited the
/// scene into the clipped layer. Presenting through `SKView` and clipping on the
/// UIKit layer paints the bin reliably.
struct BoardSKView: UIViewRepresentable {
    let scene: CompactorScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 780))
        view.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        view.allowsTransparency = false
        view.isAsynchronous = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        // XCUITest real-play targets this host for taps/swipes into SpriteKit touches.
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "gameBoard"
        view.accessibilityLabel = "Game board"
        // Seed a non-zero size before first present — zero-bound present left a grey void.
        scene.size = CGSize(width: 390, height: 780)
        present(scene, in: view)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        view.isPaused = false
        scene.isPaused = false
        if view.scene !== scene {
            present(scene, in: view)
        }
        // Keep the scene sized to the live view.
        let bounds = view.bounds
        if bounds.width > 10, bounds.height > 10 {
            let target = CGSize(width: bounds.width, height: bounds.height)
            if abs(scene.size.width - target.width) > 1 || abs(scene.size.height - target.height) > 1 {
                scene.size = target
            }
        }
    }

    private func present(_ scene: CompactorScene, in view: SKView) {
        scene.scaleMode = .resizeFill
        scene.isPaused = false
        if view.bounds.width > 10, view.bounds.height > 10 {
            scene.size = view.bounds.size
        } else if scene.size.width < 10 || scene.size.height < 10 {
            scene.size = CGSize(width: 390, height: 780)
        }
        view.presentScene(scene)
        view.isPaused = false
    }
}
