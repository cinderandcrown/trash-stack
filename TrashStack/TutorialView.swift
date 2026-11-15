// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

struct TutorialView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    @State private var step = 0

    private let steps: [(title: String, body: String, cta: String)] = [
        (
            "Drop junk items",
            "Drag cans, bottles, pipes, and crates into the 8×14 dumpster. Tap to rotate bent pieces. This is a night-shift recycle bin — not a puzzle of letter blocks.",
            "Got it"
        ),
        (
            "Recycle materials",
            "When 4 or more touching cells share a material (metal, plastic, glass, paper), they get sucked into the recycle chute. Chains can cascade when junk settles.",
            "Next"
        ),
        (
            "Slam the PRESS",
            "Placing items fills the PRESS meter. When it’s full, tap PRESS to crush the bottom two rows into scrap. That’s your timed power move — then finish order tickets and use Snatch once.",
            "Start shift"
        ),
    ]

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 20) {
                Text("NIGHT SHIFT INTRO")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(NeonTheme.teal)
                    .padding(.top, 12)

                BundleImage(name: step == 2 ? "RaccoonCheer" : "RaccoonIdle")
                    .scaledToFit()
                    .frame(height: 120)

                NeonPanel {
                    VStack(alignment: .leading, spacing: 12) {
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
                    } else {
                        profile.tutorialDone = true
                        profile.persist()
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
            .safeAreaPadding(.top, 16)
            .padding(.bottom, 12)
        }
    }
}
