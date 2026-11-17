# Trash Stack QA: commit `ac2ccc0`

**Game:** Trash Stack: Neon Blocks (`com.cinderandcrown.trashstack`), repo `cinderandcrown/trash-stack`, branch `cursor/trash-stack-native-swift-497e`
**Commit:** `ac2ccc08adfd3f48d9210e9cb5ee76827518372b` ("Fix smoke ffmpeg mux: stream-copy video instead of re-encoding")
**Baseline:** `286bb13` (5.0, `qa/286bb13`), `54cf2ce` (5.1)
**Evidence:** PR CI run `44076779739` (artifact `app-store-review-evidence`), push CI `44076771965`, TestFlight dry run `44076779680`. All green.
**Reviewer:** Fire Fox, measured-art-qa pass, 17 Nov 2026, 6:30 AM CT
**Attachments:** `CONTACT_SHEET_ac2ccc0.jpg`, `scores_ac2ccc0.json`, `evidence_ac2ccc0/` (overlays: blue = 01-title edges, red = shot edges, magenta = both)

---

## Verdict

**NO. Do not tag TestFlight.** The score is **5.0 / 10**, flat against 286bb13 (5.0) and 54cf2ce (5.1). There are **3 P0s**.

The CI is green, but **the screenshot evidence is empty**. **19 of the 20 in-app screenshots are the title screen**: gameplay, compactor, recycle, revive, base, pass, shop, notif, daily, share, streak, all 7 `mkt-*` shots, and the publisher-ident shot. Their SSIM against `01-title` is 0.954–0.995 (contact sheet; overlays are almost entirely magenta). That means none of the screens below the title were verified by this run, and this run doesn't prove the ident renders.

The real fixes since 286bb13 are good: crate odds now come from one shared table, the raccoon matte is solid, the launch logo is @3x, the 64 s music loops are in, prompts no longer stack on game-over, the 8 s launch gate is restored, and the publisher ident is built to spec in code. But the board is still unreadable (about 23% pixel coverage on a near-full bin). Recycle ghosts are still flat colored squares. The only real launch on video (the demo) held the OS launch screen for **7.0 s** and then showed a **gray board for 2.3 s**.

### Running table

| Category (weight) | 54cf2ce | 286bb13 | ac2ccc0 | Δ vs 286bb13 | Why |
|---|---:|---:|---:|---:|---|
| Fun (40%) | 4.5 | 4.5 | 4.5 | 0 | The piece shape now matches its collision footprint, and there's a "BIN ALMOST FULL" near-miss beat. But the stack still reads as scattered stickers. |
| Feel / juice | 4.0 | 5.0 | 5.0 | 0 | The ghost-snapshot fix didn't work. Flat magenta and gray squares still show at 12.1, 20, 28 and 31 s. |
| Readability | 4.5 | 3.0 | 3.0 | 0 | The near-full board is 23% covered (target ≥ 85%). Edge cells draw over the bin frame. |
| Onboarding / first 60 s | 4.0 | 5.0 | **4.5** | **−0.5 REGRESSION** | Demo launch: 7.0 s on the OS launch screen, then 2.3 s of HUD over a flat gray board. |
| Retention hooks | 6.0 | 6.0 | 6.0 | 0 | Unchanged. Streak, daily and share weren't captured (all are title shots). |
| Monetization ethics | 7.5 | 6.0 | **7.5** | +1.5 | Odds match the code through `CrateLoot`. ATT and UMP fire only on an opt-in revive tap. Notifications are asked only on a streak reward. |
| Performance | 6.0 | 6.5 | **5.5** | **−1.0 REGRESSION** | In play (11.2–24 s): 28 gaps over 50 ms, 9 over 100 ms, max 253 ms (286bb13: 19, max 180 ms). Plus the 9.6 s tap-to-board on the demo launch. |
| Distinct from falling-block classics | 6.5 | 6.5 | 6.5 | 0 | Unchanged |
| App Store readiness | 3.0 | 4.0 | 4.5 | +0.5 | Logo @3x, matte, 64 s loops, duplicate junk files deleted, odds fixed. Still has zero valid store screenshots, test AdMob IDs, stub IAP and unrecorded art provenance. |
| **Overall** | **5.1** | **5.0** | **5.0** | 0 | Not better. The evidence pipeline is broken. |

---

## 1. Launch time, measured independently

**Claimed:** 0.426 s in-app and 3.71 s wall clock (`launch-timing.txt`). **The gates were not loosened. They were tightened:**

| Gate | 54cf2ce | 286bb13 | ac2ccc0 |
|---|---|---|---|
| Wall-clock ceiling | 8 s (bash `$SECONDS`) | **45 s** (loosened in 73adbec) | **8.0 s** (host epoch at `simctl launch` → app's `first_frame_wall_epoch`) |
| In-app gate | none | none (just a comment) | **1.5 s** from the `ProcessInfo.systemUptime` stamp, which fails the run if it's missing |
| `assert_app_frame` | md5 `37615e59` | `37615e59` | `25e48fc4`. The only diff is a `raw_deadline 25` wrapper, and the thresholds are byte-identical. |
| `assert_no_missing_textures` | `f1ad67ff` | `f1ad67ff` | `f1ad67ff` (unchanged) |
| `.github/workflows/ci.yml` | n/a | n/a | Only adds `brew install ffmpeg` and a stdlib PNG check. No gate changes. |

**Problems with what the gates measure:**
1. **The in-app stamp fires on `onAppear` of a blank charcoal view** (`PublisherIdentView.bootstrapFirstFrame`), and the logo is deliberately deferred to the next frame. `onAppear` runs before the frame is committed to screen, so 0.426 s is "SwiftUI built the root view", not "pixels on glass". That's acceptable as a lower bound, but it isn't proof.
2. **Only the ident and title path is measured.** For the demo launch (`-trashStackShot demo`), `showIdent` is false and `TitleView` never appears, so no stamp is written. **That's the one launch I could measure on video, and it's slow:**

| Event (`gameplay-demo.mp4` frame PTS) | t (s) |
|---|---:|
| Springboard zoom starts (launch) | 1.593 |
| OS LaunchLogo static (frame diff < 3) until | 8.682 |
| HUD appears over a **flat gray board** | 8.90 |
| First rendered board (SpriteKit scene) | 11.193 |

**Tap → first game frame is about 9.6 s.** The launch screen holds for 7.0 s and the gray board for 2.3 s (`evidence_ac2ccc0/launch_strip_demo.jpg`). The game-scene path is doing heavy main-thread work (scene, texture or audio decode) before the first SwiftUI frame. A real player hits this path on their first tap of PLAY. Simulator cold caches inflate it, but 7 s is not noise.
3. The ident was supposed to have game assets **preloading behind it** (SPEC). Nothing preloads, so the cost just moves to the PLAY tap.

**Verdict on launch:** the gates are honest and tight for the ident path. They are **blind for the game path**, and the measured game path is about 9.6 s. → P0-2.

## 2. Publisher ident (per `/workspace/cc-splash/SPEC.txt`)

| Spec item | Result | Evidence |
|---|---|---|
| Mute logo only, no wordmark | **Pass** | `CinderCrownMute-3x.png` md5 `f4a3ffce…` matches the spec. @1x/@2x/@3x are in the catalog. It's a phoenix plus crown with no text. |
| "Cinder & Crown Creative Presents" (exact) | **Pass** (in code) | `PublisherIdentView.swift`, serif light, tracking 3.2, cream |
| No other on-screen text | **FAIL (P1)** | Adds a third line: "Cinder & Crown logo, © Cinder and Crown LLC, used by permission." The spec puts that note in the **license file**, not on screen. |
| 1.8–2.2 s total | **Pass** (by code: about 1.9 s) | Not visually verified |
| Tap to skip | Pass | `.onTapGesture { finish }` |
| Cold launch only, never on resume | Pass | `@State showIdent` in `RootView` |
| Reduce Motion | Pass | Static logo, then a 0.9 s hold |
| No ads, ATT, UMP or notification prompts during the ident | Pass | Notif prompt gated on `!showIdent`. Ads bootstrap only on the shop or a revive tap. |
| Whoosh respects the mute switch **and the app's sound setting** | **FAIL (P1)** | The default audio session (soloAmbient) respects the switch. But the Settings "Sound" toggle is `@State private var muted = false`. It isn't persisted and resets every launch, so the ident whoosh always plays. |
| Assets preload behind it | **FAIL (P1)** | No preload. See §1. |
| **Ident screenshot in the smoke artifacts** | **FAIL (P0-1)** | `00-publisher-ident.png` is the **title screen** (SSIM 0.956 vs title). It's reused from the cold-launch timing capture, which is taken after an 8 s stamp poll, long after the ~1.9 s ident ended. `assert_not_launch_splash` passes it because it isn't the LaunchLogo. |
| License note | Pass | `docs/LICENSES.md` has the exact "used by permission" line and the md5 |

## 3. Store-readiness basics

| Rule | Result | Evidence |
|---|---|---|
| Never say the forbidden falling-block brand name | **Pass in app and docs** | `git grep -i` hits only the old `docs/qa/*286bb13*` files (from my earlier report). **Redacted on this branch.** |
| Random rewards show odds | **Pass** (code) / unverified on screen | `CrateLoot.oddsDisplayLine` and `roll()` share one table, pinned by `ServicesTests`. It shows "0 (33%) / 1 (33%) / 2 (33%)", which adds up to 99% (P2: show 33.3%). The crate screen wasn't captured. |
| No nagging to buy | **Pass** | The revive sheet says "Revive once with an opt-in ad, or clock out. No purchase prompts here." ATT and UMP fire only on the opt-in revive tap. The notification ask moved to the streak reward. `maybeShowInterstitial` is still a stub. |
| Art is CC0/CC-BY/original, with a license file | **File present; provenance still unrecorded (P1)** | `LICENSES.md` calls every raster "Original… authored for this title". The painted raccoon, alley and dumpster rasters have no tool or ownership record. The file's own policy says to record the tool and ownership terms for generator-assisted rasters. Duplicate alias junk files were deleted (good). |
| Raccoon matte | **FIXED** | Idle has 121,524 opaque px (was 15,445). The eroded core is 85.7% opaque (Cheer 95.1%, Panic 95.3%). |
| Launch logo | **FIXED** | 600 px @3x (was 512 px @1x and clipped) |
| Music | **FIXED** | `game_loop` and `menu_loop` are 64.0 s (were 8 s) |

## 4. Screenshot review (every file)

| Shot | Shows | SSIM vs title | Verdict |
|---|---|---:|---|
| 00-springboard | Springboard with the icon | 0.161 | OK |
| 00-springboard-icon-crop | **Same bytes as 00-springboard** (no-Pillow fallback) | 0.161 | P2, still mislabeled |
| 00-publisher-ident | **Title** | 0.956 | **INVALID** |
| 01-title | Title | 1.000 | OK. The neon wordmark, buttons and footer read fine. |
| 02-gameplay, 03-compactor-clear, 04-recycle-combo, 05-game-over-revive | **Title** | 0.955–0.994 | **INVALID** |
| 06-base, 07-pass, 08-shop, 09-notification-prompt | **Title** | 0.954–0.992 | **INVALID** |
| 10-daily-dumpster, 11-daily-share-card, 12-streak-reward | **Title** | 0.955–0.995 | **INVALID** |
| mkt-01…07 (play, crush, recycle, junkyard, pass, shop, daily) | **Title**, with no marketing caption | 0.955–0.994 | **INVALID**. None of them can be used as App Store screenshots. |

**Root cause (P0-1):** `a169cc8` swapped `simctl terminate` for `simctl spawn <dev> killall TrashStack`. On this runner that returns **rc=2 on all 19 shots** (`smoke-step-timing.tsv`), and the `|| true` hides the failure. The title-step process keeps running. `simctl launch -trashStackShot <mode>` just brings the existing process to the front, and **the new arguments are never read**. `assert_app_frame` only checks "is this an app frame". `assert_no_missing_textures` passes on the title. The "distinctness" check compares sha256 bytes, and the animated rain and raccoon defeat it. Every gate passed on 19 identical screens. **The gates weren't loosened, but together they no longer verify anything below the title.**

**Visual bugs found in the demo video instead** (the only real look at gameplay; `evidence_ac2ccc0/`):
- **Board readability (P0-3):** the near-full board at 25.5 s is only **23.1%** covered by pieces (diff vs the empty bin; target ≥ 85%) (`board_fill_25.5s.jpg`, `board_fillmask_25.5s.png`). The "opaque material fill" in `CompactorScene` sets `colorBlendFactor`, which only tints the sprite's opaque pixels, so the transparent 60–85% of each junk tile stays see-through. Each cell is still a tiny bottle, can, plank or ring.
- **Pieces draw over the bin frame:** the edge columns and the bottom two rows sit on the metal frame and machinery. At 28 s the top rows draw above the frame lip with a pink band (`ghosts_level_regress_24-31s.jpg`, `gameover…`).
- **Flat-color recycle ghosts:** solid magenta or gray rectangles at 12.1, 20, 28 and 31 s. The new snapshot code is in place, but the output still shows `fallbackColor` squares. Most likely the cells were already cleared before `handleEvents()` takes the snapshot (not confirmed in a debugger).
- **Gray board on game launch:** HUD over a flat #808080-ish board for 2.3 s (8.9–11.2 s).
- **Demo continuity:** scripted `applyShotScenario` swaps make the level go **backwards** (LVL 2 at 9,465 → LVL 1 at 11,895 and 14,936 → LVL 2). The game-over sheet says **Score 8,800** right after the HUD showed **21,595**.
- **Overlapping text:** "Level 2" draws over a fading "RECYCLE" banner (reads "Level 2E" at 31 s). "+325" and "+329" score pips overlap. Pips cover the chute labels.
- **Chute labels:** two different "P" chutes (orange paper, magenta plastic) with letters only. Ambiguous.
- **Positive:** the "BIN ALMOST FULL" lip warning and the ONE MORE? sheet render cleanly with no clipping. The demo audio note is now honest (real `game_loop.wav` with no fake SFX offsets).

---

## Ranked fix list

### P0 (blocks TestFlight)
1. **P0-1 Smoke screenshots must show their target screen.** Go back to `simctl terminate` (with a deadline), or check `killall`'s exit code and fall back to `terminate`. After the kill, confirm the PID is gone before launching. Add a **per-mode check**: every shot except `title` must have SSIM < 0.85 against `01-title.png`, plus a mode-specific marker (the board frame for game modes, the header text for meta screens, the caption panel for `mkt-*`). Fail the run otherwise. Capture the ident with `-trashStackShot ident` (holds the final pose). Don't reuse the timing frame. Replace the sha256 distinctness check with a pairwise SSIM < 0.95 check.
2. **P0-2 Game-path launch.** Demo launch: 7.0 s on the OS launch screen, then 2.3 s of gray board (9.6 s tap → board). Profile it with the Instruments App Launch template. Move SKScene, texture and audio decode off the first frame, and preload them during the ident as the spec requires. Stamp the first **rendered** game frame (`CompactorScene.didMove` plus one `update`) and gate it at ≤ 1.5 s after the PLAY tap, and at ≤ 8 s wall clock from launch for `shot=demo`. Show the board's dark backdrop, never flat gray.
3. **P0-3 Board readability (carried over from 286bb13, still failing).** Each locked cell needs a solid material tile: draw an opaque rounded-square base in the material color, and put the junk icon on top at ≤ 60% of the cell. Remember that `colorBlendFactor` can't fill transparent pixels. *Metric:* ≥ 85% coverage of occupied cells in a near-full-board frame (this build: 23.1%). Also keep every cell inside the bin's inner rectangle: no drawing over the frame sides, the floor or above the lip.

### P1 (fix before a useful playtest)
1. **Recycle ghosts:** take the snapshot *before* any render that clears the cells (capture it in the engine event or before `render(immediate:)`). No flat squares.
2. **Ident:** remove the on-screen "used by permission" line (keep it in `LICENSES.md`). Persist the Sound setting (`@AppStorage`), apply it at launch, and skip the whoosh when sound is off.
3. **Demo continuity:** no state swaps that roll the level back or change the score. Build the near-miss and game-over from the live run (rig the piece queue), so the game-over score matches the HUD.
4. **Art provenance:** record how the raccoon, alley and dumpster rasters were made (tool and ownership terms), or replace them with CC0/CC-BY or confirmed-original art.
5. **Frame pacing:** in-play gaps over 50 ms went from 19 to 28, with max 253 ms. Find the spikes (likely `engine.attach` / `detach` of an `AVAudioPlayerNode` per SFX, plus particle bursts). Pool the player nodes.

### P2 (polish)
1. Banner queue: never draw two banners at once ("Level 2" over "RECYCLE"). Stack or offset score pips so they don't overlap each other or the chutes.
2. Chute labels: use distinct icons or two-letter labels (PA / PL), ≥ 11 pt.
3. Odds line: show 33.3% so the numbers add up to 100%.
4. `00-springboard-icon-crop.png` is still the full frame. Do the crop with stdlib or `sips`.
5. Game-over line "streak 0d": hide it when the streak is 0.

---

## Not verified this round
Every screen except the title and in-game HUD (base, pass, shop, notif, daily, share, streak, marketing, crate odds UI, ident visuals); physical device; haptics; in-app audio. These all need a rerun after P0-1.
