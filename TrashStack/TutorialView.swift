// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

/// ~30s FTUE: move → rotate → clusters → press. Juicy vertical slice only.
struct TutorialView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    @State private var step = 0

    private let steps: [(title: String, body: String, cue: String, cta: String)] = [
        (
            "Drag to move",
            "Drag anywhere on the dumpster to slide the falling junk left or right. Placement doesn’t matter — grab from anywhere.",
            "MOVE",
            "Got it"
        ),
        (
            "Tap to rotate",
            "Tap the board once to rotate bent pipes and long junk. Square crates and tires don’t need a spin.",
            "ROTATE",
            "Next"
        ),
        (
            "Make a cluster",
            "Connect 4+ cells of the same material — metal, plastic, glass, or paper. They suck into the chute. Chains feel great.",
            "CLUSTER",
            "Next"
        ),
        (
            "Slam the PRESS",
            "Placing junk fills the PRESS meter. When it’s ready, tap PRESS to crush the bottom two rows into scrap.",
            "PRESS",
            "Start shift"
        ),
    ]

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 16) {
                Text("NIGHT SHIFT INTRO")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(NeonTheme.teal)
                    .padding(.top, 8)

                Text("About 30 seconds")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NeonTheme.muted)

                BundleImage(name: step >= 2 ? "RaccoonCheer" : "RaccoonIdle")
                    .scaledToFit()
                    .frame(height: 100)

                Text(steps[step].cue)
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(NeonTheme.teal)
                    .clipShape(Capsule())

                NeonPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(steps[step].title)
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                        Text(steps[step].body)
                            .foregroundStyle(Color.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Step \(step + 1) of \(steps.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NeonTheme.magenta)
                    }
                }
                .padding(.horizontal, 16)

                NeonButton(title: steps[step].cta) {
                    if step < steps.count - 1 {
                        step += 1
                        AudioService.shared.playSFX("ui")
                    } else {
                        profile.tutorialDone = true
                        profile.persist()
                        AudioService.shared.playSFX("levelup")
                        screen = .game
                    }
                }
                .padding(.horizontal, 16)

                Button("Skip") {
                    profile.tutorialDone = true
                    profile.persist()
                    screen = .title
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(NeonTheme.muted)

                Spacer(minLength: 0)
            }
            .safeAreaPadding(.top, 12)
            .safeAreaPadding(.bottom, 12)
        }
    }
}
