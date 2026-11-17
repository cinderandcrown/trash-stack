# Trash Stack (Native iOS)

**Recycling Night Shift** — neon dumpster game by **Cinder and Crown LLC**.

Match materials, slam the press, fill order tickets. See `docs/DESIGN.md`.

This branch is a **native Swift** rewrite (SpriteKit + SwiftUI). The Capacitor/web packaging work stays on PR #1 as reference and is **not** merged.

- **Bundle ID:** `com.cinderandcrown.trashstack`
- **Team:** `GDNRT9DJ58`
- **App Store Connect Apple ID:** `6834995780`
- **Home-screen name:** Trash Stack

## Structure

| Path | Role |
|------|------|
| `Packages/GameCore` | Pure Swift rules, scoring, bag RNG, economy/season JSON |
| `Packages/GameRender` | SpriteKit `CompactorScene` (baked colors, no glow spam) |
| `Packages/Services` | StoreKit 2, ads policy, notifications, haptics, audio, GameKit stubs |
| `TrashStack/` | SwiftUI app shell + meta screens |
| `Config/` | `economy.json` + season JSON |
| `docs/ECONOMY.md` | F2P / compliance tuning |

## Develop

```bash
brew install xcodegen
xcodegen generate
open TrashStack.xcodeproj
```

```bash
cd Packages/GameCore && swift test
```

## CI

Mirrors [magpie](https://github.com/cinderandcrown/magpie):

- PRs / pushes: build, unit tests, simulator smoke (screenshots + 45–60s video)
- Artifact: `app-store-review-evidence`
- TestFlight upload **only** on `testflight/*` tags (agents push **no** tags)

Android is a later native project — not in this branch.
