// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

struct TitleView: View {
    @Binding var screen: AppScreen
    @Binding var showNotifPrompt: Bool
    @EnvironmentObject var profile: PlayerProfile

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            TrashPandaMascot()
                .frame(width: 96, height: 96)
            Text("TRASH STACK")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Color.cyan, Color.pink], startPoint: .leading, endPoint: .trailing)
                )
            Text("Neon junk. Night shift.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Chip(label: "SCRAP", value: "\(profile.scrap)")
                Chip(label: "GEMS", value: "\(profile.gems)", tint: .purple)
            }
            Button {
                AdsService.shared.noteRunStarted()
                screen = .game
            } label: {
                Text("Play")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan.opacity(0.9))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 28)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetaButton("Junkyard") { screen = .base }
                MetaButton("Season Pass") { screen = .pass }
                MetaButton("Shop") { screen = .shop }
                MetaButton("Quests") { screen = .quests }
                MetaButton("Settings") { screen = .settings }
                MetaButton("Spin") { AudioService.shared.blip(frequency: 660) }
            }
            .padding(.horizontal, 24)

            Text("Free to play · odds shown · no real-money gambling")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct TrashPandaMascot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
            Circle()
                .stroke(Color.cyan.opacity(0.7), lineWidth: 3)
            // ears
            Circle().fill(Color(red: 0.12, green: 0.12, blue: 0.14)).frame(width: 28, height: 28).offset(x: -30, y: -34)
            Circle().fill(Color(red: 0.12, green: 0.12, blue: 0.14)).frame(width: 28, height: 28).offset(x: 30, y: -34)
            // mask
            Capsule().fill(Color.black.opacity(0.55)).frame(width: 70, height: 28).offset(y: -4)
            // eyes
            Circle().fill(Color.cyan).frame(width: 10, height: 10).offset(x: -14, y: -6)
            Circle().fill(Color.cyan).frame(width: 10, height: 10).offset(x: 14, y: -6)
            // nose
            Capsule().fill(Color.pink.opacity(0.85)).frame(width: 14, height: 8).offset(y: 10)
        }
        .accessibilityLabel("Trash Panda")
    }
}

struct Chip: View {
    let label: String
    let value: String
    var tint: Color = .cyan
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(tint)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MetaButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(.white)
    }
}
