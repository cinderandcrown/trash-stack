// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import UIKit
import Services
import GameRender

/// Asset-catalog first, then app Resources/UI, then GameRender package textures.
enum BundleArt {
    static func uiImage(_ name: String) -> UIImage? {
        if let img = UIImage(named: name) { return img }
        for bundle in JunkTextureLoader.candidateBundles() {
            if let img = UIImage(named: name, in: bundle, compatibleWith: nil) { return img }
            for sub in ["UI", "Resources/UI", "Junk", "HUD", "Resources/Junk", "Resources/HUD"] {
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
        return JunkTextureLoader.imageFromModule(named: name)
    }
}

struct BundleImage: View {
    let name: String
    var body: some View {
        if let img = BundleArt.uiImage(name) {
            Image(uiImage: img).resizable()
        } else {
            Color.white.opacity(0.08)
        }
    }
}

enum NeonTheme {
    static let bgTop = Color(red: 0.03, green: 0.03, blue: 0.07)
    static let bgBottom = Color(red: 0.06, green: 0.04, blue: 0.09)
    /// Dim play chrome — must not compete with the neon dumpster board.
    static let playChrome = Color(red: 0.02, green: 0.02, blue: 0.05)
    static let panel = Color(red: 0.06, green: 0.07, blue: 0.11)
    static let panelStroke = Color(red: 0.0, green: 0.75, blue: 0.78)
    static let magenta = Color(red: 0.88, green: 0.22, blue: 0.68)
    static let teal = Color(red: 0.0, green: 0.82, blue: 0.86)
    static let text = Color.white
    static let muted = Color.white.opacity(0.62)

    static var alleyGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }
}

struct NeonPanel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundStyle(NeonTheme.teal)
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NeonTheme.panel.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(colors: [NeonTheme.teal.opacity(0.8), NeonTheme.magenta.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.5
                        )
                )
        )
    }
}

struct NeonButton: View {
    let title: String
    var style: Style = .primary
    var action: () -> Void

    enum Style { case primary, secondary, ghost }

    var body: some View {
        Button(action: {
            AudioService.shared.playSFX("ui")
            HapticsService.shared.tap()
            action()
        }) {
                Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(foreground)
                .background { background }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(border, lineWidth: style == .ghost ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary: return .black
        case .secondary, .ghost: return .white
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            LinearGradient(colors: [NeonTheme.teal, NeonTheme.teal.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
        case .secondary:
            LinearGradient(colors: [NeonTheme.magenta.opacity(0.85), NeonTheme.magenta.opacity(0.55)], startPoint: .leading, endPoint: .trailing)
        case .ghost:
            Color.white.opacity(0.2)
        }
    }

    private var border: Color {
        style == .ghost ? NeonTheme.teal : .clear
    }
}

struct CurrencyChip: View {
    enum Kind { case scrap, gems }
    let kind: Kind
    let value: Int

    var body: some View {
        HStack(spacing: 6) {
            BundleImage(name: kind == .scrap ? "ScrapIcon" : "GemIcon")
                .frame(width: 18, height: 18)
            Text("\(value)")
                .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.bold))
                .foregroundStyle(kind == .scrap ? NeonTheme.teal : NeonTheme.magenta)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct AlleyBackdrop: View {
    var body: some View {
        ZStack {
            NeonTheme.alleyGradient.ignoresSafeArea()
            BundleImage(name: "AlleyBackground")
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(0.9)
            // Rain streaks (lightweight SwiftUI, not SpriteKit glow nodes)
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    for i in 0..<28 {
                        let x = (CGFloat(i) / 28) * size.width + CGFloat(sin(t + Double(i))) * 8
                        let y = CGFloat((t * 180 + Double(i) * 47).truncatingRemainder(dividingBy: Double(size.height + 40))) - 20
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x - 4, y: y + 16))
                        ctx.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
