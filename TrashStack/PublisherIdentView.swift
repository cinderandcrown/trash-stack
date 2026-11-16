// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

/// Cold-launch studio ident — Cinder & Crown Creative Presents.
/// First paint is solid charcoal only (stamp launch timing); logo/embers deferred one frame.
struct PublisherIdentView: View {
    /// When true (smoke `-trashStackShot ident`), hold the final pose for a screenshot.
    var holdForShot: Bool = false
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLogoArt = false
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.92
    @State private var titleOpacity: Double = 0
    @State private var creditOpacity: Double = 0
    @State private var glowPulse: Double = 0.35
    @State private var sweepX: CGFloat = -0.6
    @State private var showEmbers = false
    @State private var finished = false

    private let crimson = Color(red: 0x6E / 255, green: 0x0F / 255, blue: 0x16 / 255)
    private let gold = Color(red: 0xF5 / 255, green: 0xA6 / 255, blue: 0x23 / 255)
    private let cream = Color(red: 0.96, green: 0.93, blue: 0.86)
    private let charcoal = Color(red: 0.06, green: 0.05, blue: 0.05)

    var body: some View {
        ZStack {
            charcoal.ignoresSafeArea()
            if showLogoArt {
                RadialGradient(
                    colors: [crimson.opacity(0.55 * glowPulse), charcoal.opacity(0)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 340
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if showEmbers, !reduceMotion {
                    EmberField(gold: gold, crimson: crimson)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 22) {
                    Spacer(minLength: 40)
                    ZStack {
                        BundleImage(name: "CinderCrownMute")
                            .scaledToFit()
                            .frame(width: 168, height: 168)
                            .opacity(logoOpacity)
                            .scaleEffect(logoScale)
                            .shadow(color: gold.opacity(0.35 * glowPulse), radius: 28)
                            .accessibilityLabel("Cinder and Crown")

                        if !reduceMotion {
                            LinearGradient(
                                colors: [.clear, gold.opacity(0.55), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 56, height: 180)
                            .rotationEffect(.degrees(18))
                            .offset(x: sweepX * 140)
                            .blendMode(.plusLighter)
                            .opacity(logoOpacity)
                            .mask(
                                BundleImage(name: "CinderCrownMute")
                                    .scaledToFit()
                                    .frame(width: 168, height: 168)
                            )
                            .allowsHitTesting(false)
                        }
                    }

                    Text("Cinder & Crown Creative Presents")
                        .font(.system(size: 17, weight: .light, design: .serif))
                        .tracking(3.2)
                        .foregroundStyle(cream.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .opacity(titleOpacity)
                        .padding(.horizontal, 28)

                    Text("Cinder & Crown logo, © Cinder and Crown LLC, used by permission.")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .tracking(0.4)
                        .foregroundStyle(gold.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .opacity(creditOpacity)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 48)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish(skipped: true) }
        .onAppear(perform: bootstrapFirstFrame)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Skips the studio intro")
    }

    private func bootstrapFirstFrame() {
        // Honest first-frame stamp BEFORE decoding the mute logo.
        LaunchTiming.markFirstTitleFrame()
        Task { @MainActor in
            await Task.yield()
            showLogoArt = true
            runSequence()
        }
    }

    private func runSequence() {
        if reduceMotion {
            logoOpacity = 1
            logoScale = 1
            titleOpacity = 1
            creditOpacity = 1
            glowPulse = 0.5
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                if !holdForShot { finish(skipped: false) }
            }
            return
        }

        withAnimation(.easeOut(duration: 0.55)) {
            logoOpacity = 1
            logoScale = 1
            glowPulse = 0.85
        }
        withAnimation(.easeInOut(duration: 1.1)) {
            sweepX = 0.7
        }
        Task { @MainActor in
            await Task.yield()
            showEmbers = true
            AudioService.shared.playSFX("ember_whoosh", pitch: 0.95)
            try? await Task.sleep(nanoseconds: 380_000_000)
            withAnimation(.easeOut(duration: 0.35)) {
                titleOpacity = 1
                creditOpacity = 1
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            if holdForShot { return }
            withAnimation(.easeIn(duration: 0.32)) {
                logoOpacity = 0
                titleOpacity = 0
                creditOpacity = 0
                glowPulse = 0.2
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            finish(skipped: false)
        }
    }

    private func finish(skipped: Bool) {
        guard !finished else { return }
        finished = true
        onFinished()
        _ = skipped
    }
}

/// Lightweight drifting ember particles (Canvas) — only after first paint.
private struct EmberField: View {
    let gold: Color
    let crimson: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                Self.drawEmbers(ctx: ctx, size: size, t: t, gold: gold, crimson: crimson)
            }
        }
        .ignoresSafeArea()
    }

    private static func drawEmbers(
        ctx: GraphicsContext,
        size: CGSize,
        t: TimeInterval,
        gold: Color,
        crimson: Color
    ) {
        let band = Double(size.height) * 0.55
        for i in 0..<18 {
            let seed = Double(i) * 17.13
            let xNorm = sin(t * 0.35 + seed) * 0.5 + 0.5
            let x = CGFloat(xNorm) * size.width
            let speed = 18.0 + Double(i % 5)
            let travel = (t * speed + seed * 9).truncatingRemainder(dividingBy: band)
            let y = CGFloat(band) - CGFloat(travel)
            let r = CGFloat(1.2 + Double(i % 3))
            let rect = CGRect(x: x, y: y, width: r, height: r * 1.6)
            let col: Color = (i % 2 == 0) ? gold.opacity(0.55) : crimson.opacity(0.45)
            ctx.fill(Path(ellipseIn: rect), with: .color(col))
        }
    }
}
