// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

struct TutorialView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    @State private var step = 0

    private let steps: [(title: String, body: String)] = [
        ("Drag to shove junk", "Slide left or right to steer the falling scrap across the dumpster."),
        ("Tap to twist", "Tap once to rotate. Swipe down to soft-drop. Flick down to slam."),
        ("Crush & recycle", "Fill a row for a hydraulic crush. Match 3+ of the same material to recycle. Swipe up to stash."),
    ]

    var body: some View {
        ZStack {
            AlleyBackdrop()
            NeonPanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("NIGHT SHIFT 101")
                        .font(.system(.title2, design: .rounded).weight(.black))
                        .foregroundStyle(NeonTheme.teal)
                    Text("Step \(step + 1) of 3")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NeonTheme.magenta)
                    Text(steps[step].title)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text(steps[step].body)
                        .foregroundStyle(NeonTheme.muted)
                    Image("RaccoonIdle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                    NeonButton(title: step < 2 ? "Next" : "Into the alley") {
                        if step < 2 {
                            step += 1
                        } else {
                            profile.tutorialDone = true
                            profile.persist()
                            AudioService.shared.playMusic("game_loop")
                            screen = .game
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
