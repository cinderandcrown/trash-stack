// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import UIKit
import GameRender

/// Plays Higgsfield bandit sprite loops (idle_front / cheer / panic / …) beside the board.
/// Falls back to the static mood head when a loop folder is missing.
struct BanditLoopView: View {
    let mood: CompactorScene.RaccoonMood
    var size: CGFloat = 72

    @State private var frameIndex = 0
    @State private var frames: [UIImage] = []
    @State private var fallbackName = "RaccoonIdle"

    private var loopFolder: String {
        switch mood {
        case .idle: return "idle_front"
        case .cheer: return "cheer"
        case .panic: return "panic"
        case .disco: return "disco_dance"
        case .gameOver: return "gameover"
        }
    }

    private var staticFallback: String {
        switch mood {
        case .cheer: return "RaccoonCheer"
        case .panic: return "RaccoonPanic"
        case .disco:
            return BundleArt.uiImage("RaccoonDisco") != nil ? "RaccoonDisco" : "RaccoonCheer"
        case .gameOver: return "RaccoonGameOver"
        case .idle: return "RaccoonIdle"
        }
    }

    var body: some View {
        Group {
            if let img = frames.isEmpty ? nil : frames[frameIndex % max(frames.count, 1)] {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if let img = BundleArt.uiImage(fallbackName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white.opacity(0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("The Bandit")
        .task(id: mood) {
            reload(for: mood)
            while !Task.isCancelled {
                let count = frames.count
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard count > 1 else { continue }
                frameIndex = (frameIndex + 1) % count
            }
        }
    }

    private func reload(for mood: CompactorScene.RaccoonMood) {
        fallbackName = staticFallback
        frames = Self.loadLoop(named: loopFolder)
        frameIndex = 0
    }

    /// Loads uniquely named `BanditLoops/<name>_XX.png` (XcodeGen flattens folders;
    /// duplicate `frame_00.png` names collide in the app bundle).
    static func loadLoop(named name: String) -> [UIImage] {
        var images: [UIImage] = []
        let bundles = JunkTextureLoader.candidateBundles()
        for i in 0..<24 {
            let base = String(format: "%@_%02d", name, i)
            var found: UIImage?
            for bundle in bundles {
                let candidates: [(String?, String)] = [
                    ("BanditLoops", base),
                    ("Resources/BanditLoops", base),
                    (nil, base),
                ]
                for (sub, resource) in candidates {
                    let url: URL?
                    if let sub {
                        url = bundle.url(forResource: resource, withExtension: "png", subdirectory: sub)
                    } else {
                        url = bundle.url(forResource: resource, withExtension: "png")
                    }
                    if let url, let img = UIImage(contentsOfFile: url.path) {
                        found = img
                        break
                    }
                    if let img = UIImage(named: resource, in: bundle, compatibleWith: nil) {
                        found = img
                        break
                    }
                }
                if found != nil { break }
            }
            guard let img = found else { break }
            images.append(img)
        }
        return images
    }
}
