# Game Center — Trash Stack

Config only via App Store Connect API. Nothing here submits or releases an App Store version.

## TestFlight path (source of truth)

`testflight.yml` runs **Configure Game Center** after `ensure-bundle-id` and **before** archive / App Store export:

```text
ensure-bundle-id
→ configure-game-center   # App ID GAME_CENTER + LBs + achievements
→ xcodegen / archive
→ exportArchive (-allowProvisioningUpdates)  # profile regenerates with GC
→ check_signed_app (requires com.apple.developer.game-center)
```

Idempotent — safe on every tag upload and every PR that touches the TestFlight scripts.

```bash
# Same command the workflow runs (needs ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH)
python3 scripts/appstore_connect.py configure-game-center \
  --bundle-id com.cinderandcrown.trashstack
```

### What that enables

1. **App ID capability** `GAME_CENTER` via `POST /v1/bundleIdCapabilities`  
   Confirmed with a re-list. Cloud-managed signing (`signingStyle: automatic` + `-allowProvisioningUpdates`) regenerates the App Store profile so the IPA carries `com.apple.developer.game-center`.
2. **gameCenterDetail** for the ASC app (when the app record exists).
3. Leaderboards / achievements / cross-game group (create-if-missing; 409/422 treated as already present).

| Kind | Vendor ID | Notes |
|------|-----------|-------|
| Leaderboard | `trashstack_endless` | All-time high score |
| Leaderboard | `trashstack_daily` | Daily Dumpster |
| Leaderboard | `trashstack_weekly` | Weekly tournament (7-day seed) |
| Achievements | see `AchievementID.allConfigured` | Incl. TRASH TALK + Bandit of Both Worlds |
| Group | `Cinder Crown Bandit Universe` | Cross-game with Neon City Bandit |

## Entitlement (app)

`TrashStack/TrashStack.entitlements` → `com.apple.developer.game-center`.

Auth is non-blocking (`GKLocalPlayer.authenticateHandler`). The game is fully playable signed out.

## TRASH TALK / weekly / cross-game

See prior sections in git history and `TrashTalk.swift` — junk rules, weekly seed, shared achievement `cc_bandit_of_both_worlds`. No paid entries, wagers, or real-value prizes.
