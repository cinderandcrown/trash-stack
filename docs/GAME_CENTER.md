# Game Center — Trash Stack

Config only via App Store Connect API. Nothing here submits or releases an App Store version.

## Enable + catalogs

```bash
# Requires ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8)
python3 scripts/appstore_connect.py configure-game-center \
  --bundle-id com.cinderandcrown.trashstack
```

Creates / reuses:

| Kind | Vendor ID | Notes |
|------|-----------|-------|
| Leaderboard | `trashstack_endless` | All-time high score |
| Leaderboard | `trashstack_daily` | Daily Dumpster |
| Leaderboard | `trashstack_weekly` | Weekly tournament (7-day seed) |
| Achievements | see `AchievementID.allConfigured` | ~20 ids including TRASH TALK |
| Group | `Cinder Crown Bandit Universe` | Cross-game with Neon City Bandit |

## Entitlement

`TrashStack/TrashStack.entitlements` → `com.apple.developer.game-center`.

Auth is non-blocking (`GKLocalPlayer.authenticateHandler`). The game is fully playable signed out.

Access point: on title / TRASH TALK results (`GKAccessPoint`).

## TRASH TALK

Real-time 1v1 via `GKMatchmaker` (quick match + invite). Shared piece seed. Junk rows:

| Clears in one recycle wave | Junk rows sent |
|----------------------------|----------------|
| 1 | 0 |
| 2 | 1 |
| 3 | 2 |
| 4+ | 4 |
| + combo | +(combo−1) |

Warning meter (~1.35s) before junk lands. Last bin standing wins. Disconnect → remaining player wins. Bot fallback after 20s, labeled **Dumpster Bot**. Rematch + countdown included. Wire messages are tiny (lock / junk / digest / topOut / rematch).

No paid entries, wagers, or real-value prizes.

## Weekly tournament

`WeeklyTournament.seed()` — same UTC ISO-week seed for everyone. Scores also go to `trashstack_weekly`. Modes → Weekly Tournament starts Endless with that seed.

## Cross-game: Bandit of Both Worlds

Shared achievement vendor id (both apps):

`cc_bandit_of_both_worlds`

Both games join the Game Center group **Cinder Crown Bandit Universe**. Unlocking in one title progresses the shared achievement; each game may grant a local Bandit outfit when percent hits 100. Coordinate the same id + group name with the Neon City Bandit agent — do not invent a second identifier.
