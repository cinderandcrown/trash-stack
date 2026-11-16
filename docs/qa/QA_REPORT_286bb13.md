# Trash Stack QA — commit `286bb13`

**Game:** Trash Stack (Recycling Night Shift), repo `cinderandcrown/trash-stack`, PR #2, branch `cursor/trash-stack-native-swift-497e`
**Commit:** `286bb13fc86c261d82876034df0df529ca6040d7` (“Install ffmpeg on CI and harden demo audio mux”)
**Baseline:** `54cf2ce` (QA 5.1 / fun 4.5, `docs/qa/QA_REPORT_54cf2ce.md` on `qa/54cf2ce`)
**Evidence:** green push CI run `43949149537` (artifact `app-store-review-evidence`), compared to the same fixed references used for 54cf2ce (PR CI run `43788946315` artifacts)
**Reviewer:** Fire Fox, measured-art-qa pass, 16 Nov 2026 (America/Chicago)
**Attachments:** `CONTACT_SHEET_286bb13.jpg`, `scores_286bb13.json`, `diff_286bb13_vs_54cf2ce.json`, `overlays_286bb13/` (blue = 54cf2ce edges, red = 286bb13 edges, 50% blend)

> Tip `c306446` (after this build) changes only `scripts/simulator_smoke.sh` (polls for the title frame). It has no app-code changes, so this review applies to it too.

---

## Verdict

**NO. Do not tag TestFlight.** The bar is zero P0s and clearly better than 5.1. This build has **4 P0s** and scores **5.0 / 10** (fun **4.5**, flat).

The agent fixed the two most visible P0s from last round. The **app icon is real** and the **raccoon PNGs have true alpha**. The juice numbers went up across the board. But the same commit **wrecked board readability**: junk is now drawn as small silhouettes floating in mostly empty cells. The falling piece's art **does not rotate** with its collision shape. Leftover 2×2 pieces overlap their neighbours. In a match puzzle, the player has to read the stack at a glance, so this cancels out the juice gains.

Launch is still **~3.9 s from tap to first meaningful frame** (budget 1.5 s). The new launch gate does not measure in-app paint at all, and its ceiling was quietly raised from 8 s to 45 s. The crate screen shows **odds that do not match the code**.

| Category | 54cf2ce | 286bb13 | Δ | Notes |
|---|---:|---:|---:|---|
| Fun (40%) | 4.5 | 4.5 | 0 | Juice is up, but you can't read the board and the piece art doesn't match its shape. The autoplay bin never gets above ~3 rows, so there's no tension. |
| Feel / juice | 4.0 | 5.0 | +1.0 | Shake 6→10 / 12→16 pt, hit-stop 40→60 / 90→120 ms, suck 0.25→0.5 s into visible chutes, 10–60 particles, score pips, RECYCLE / CHAIN banners, SFX 0.42–0.55 s. The recycle ghost is still a flat untextured square, and the music loop is still 8 s. |
| Readability | 4.5 | **3.0** | **−1.5 REGRESSION** | See P0-1 and P0-2 |
| Onboarding / first 60 s | 4.0 | 5.0 | +1.0 | Interactive FIRST SHIFT with a gifted metal cluster (`ftue` stage). Splash is still 3.5 s. FTUE is not in the smoke evidence (`tutorialDone=true`). |
| Retention hooks | 6.0 | 6.0 | 0 | Facades are honestly hidden (Shift, Quests). The crate now shows its loot. There are fewer hooks, but they are truthful. |
| Monetization ethics | 7.5 | **6.0** | **−1.5 REGRESSION** | Crate odds are wrong (P0-4). ATT / UMP prompts and the notification prompt fire right after the first game-over (P1-3). The shop is now de-emphasized and the $19.99 pack was renamed “Neon Haul” (good). |
| Performance | 6.0 | 6.5 | +0.5 | In-play gaps >50 ms: 19 (max 180 ms) between 5 and 35 s. Splash hold is 4.75→3.5 s. |
| Distinct from falling-block classics | 6.5 | 6.5 | 0 | Unchanged |
| App Store readiness | 3.0 | 4.0 | +1.0 | Real icon, `docs/LICENSES.md`, true alpha. Still has test AdMob IDs, stub IAP, an incomplete privacy manifest and a clipped splash. |
| **Overall** | **5.1** (4.9 with the same formula) | **5.0** | ≈0 | Not clearly better |

---

## 1. P0 re-check from 54cf2ce

### App icon: **FIXED (pass)**
`AppIcon-1024.png` is 1024×1024 RGB, **no alpha**, ~7.7k unique colors (sampled), vs 2 before. It shows a neon bin with the raccoon inside, scan lines and material bars. The catalog uses the single-size universal 1024 entry (`Contents.json` has one image), so Xcode generates every other size. I rendered it at 180/120/87/60/40 px (contact sheet, panel 2) and it reads as a neon bin at all sizes. The Springboard capture `00-springboard.png` shows it installed. Note that `00-springboard-icon-crop.png` is actually the full frame (the no-Pillow fallback), so that crop artifact is mislabeled.
*P2:* the raccoon takes up only a small part of the icon and is unreadable at 60/40 px. The inner neon border sits right on the iOS corner mask. Make the raccoon face ~50% of the canvas.

### Raccoon alpha: **FIXED numerically, with a quality caveat (P1)**
In all three copies (Assets.xcassets, Resources/UI, GameRender/HUD), the files are identical by md5. All four corners have alpha 0. The transparent / partial / opaque pixel counts (out of 262,144) are:

| Sprite | Transparent | Partial alpha | Opaque | Mean alpha |
|---|---:|---:|---:|---:|
| Idle | 152,559 | 94,140 | 15,445 | 51.5 / 255 |
| Cheer | 146,828 | 72,039 | 43,277 | 74.0 / 255 |
| Panic | 150,647 | 69,509 | 41,988 | 75.1 / 255 |

This compares with 0 transparent pixels in 54cf2ce, and the checkerboard is gone. However, the alpha was produced by **luminance keying**: dark fur and jackets became semi-transparent. On white, the raccoons turn into ghosts (contact sheet, panel 2). Idle is only 5.9% opaque, and blocky ~8 px stair-step remnants of the old checker show along the Idle silhouette. On the dark UI this mostly passes, but alley textures will show through the body. `AssetAlphaTests` only checks corners and transparent > 1000, so it can't catch this.
**Fix:** re-cut with a real matte (segment the subject, then fill the interior to alpha 255 and keep soft edges only on the outline). Add a test that the interior is ≥ 85% opaque inside the silhouette bounding box's eroded core.

### Launch time: **NOT FIXED (P0-3)**. Measured independently from `gameplay-demo.mp4` frame PTS

| Event | t (s) |
|---|---:|
| Springboard → app zoom begins (tap equivalent: `simctl launch`) | 1.030 |
| Splash fully on screen | 1.257 |
| Splash static (frame diff < 0.05) until | 4.752 |
| Crossfade to game; first fully opaque HUD + board frame | 4.935 |

**Tap → first meaningful frame ≈ 3.9 s. Splash hold ≈ 3.5 s** (54cf2ce: 4.75 s hold). It's 26% better, but it's **2.6× the 1.5 s budget**. This run passes `-trashStackSkipAds`, so the remaining stall is **not** ATT, UMP or GAD. Something else on the main thread holds first paint, most likely the SpriteKit scene, texture or audio prepare before the first SwiftUI frame. Instrument it before guessing.

**The splash is stretched and clipped.** `LaunchLogo.imageset` declares only a **1x** 512 px PNG, so iOS draws it at 512 pt on a 402 pt-wide screen. That's 127% of the screen width, and the neon card is cut off on both sides (contact sheet panel 1; `01-title` overlay).
**Fix:** ship the logo at @3x (e.g. 600 px @3x ≈ 200 pt), or use a solid-color launch screen with a centered mark.

### 73adbec gate audit: **NOT honest (P0-3, gate)**
- The commit message says it measures in-app paint. **It does not.** There is no in-app first-paint timestamp anywhere in the repo (no signpost, `CFAbsoluteTime` or uptime capture). `LAUNCH_DT` is still bash `$SECONDS` (integer) around `simctl launch` + polling + `sleep 0.8` + `simctl io screenshot`.
- **The ceiling was loosened from 8 s to 45 s** (in the 73adbec diff, `> 8` became `> 45`). The reason given is “pathological ceiling”, and the reported number is **16 s**, which would have failed the old gate. Per the skill, loosening a gate needs a written justification. Calling this metric “in-app <1.5 s” in `launch-timing.txt` is unsupported: the 1.5 s is a comment, not a measurement.
- `assert_app_frame` **passes on the splash**. `01-title.png` in this run's evidence is the **launch splash, not the title** (SSIM 0.305 vs the 54cf2ce title). The title screen was not captured or verified this build. c306446's polling loop has the same blind spot.
- **ATT / UMP / GAD deferral:** cold launch no longer awaits `AdsBootstrap.start()` before paint (good). `.task` sleeps 300 ms, then StoreKit and GameKit run, and `AdsBootstrap.start()` runs only if `firstWin` is set. But `firstWin` flips at the **first game-over with score > 0**. That game-over triggers `AdsBootstrap.startAfterFirstWinIfNeeded()` and the **ATT system prompt + UMP consent**, then the notification prompt. That's up to three prompts stacked right after a loss (see P1-3). From then on, every cold launch runs `AdsBootstrap.start()` (UMP refresh, `GADMobileAds.start`) about 300 ms after first paint, which is never measured.
**Fix:** record `ProcessInfo.systemUptime` at `main` and at the first `TitleView.onAppear` / first `CompactorScene.didMove`. Write the delta to `UserDefaults`. Have smoke read it with `simctl spawn defaults read` and fail if it's > 1.5 s. Restore a wall-clock ceiling ≤ 8 s. Make `assert_app_frame` reject the splash (SSIM vs `LaunchLogo` > 0.8 means fail).

## 2. 04-recycle-combo capture: **assert not loosened (pass), timing loosened (documented)**
`assert_app_frame()` and `assert_no_missing_textures()` are **byte-identical** between 54cf2ce and 286bb13 (md5 `37615e59…` / `f1ad67ff…`). What changed for `recycle` / `mkt-recycle` is the retry policy: attempts 2→3, settle 5→7 s + 1.1 s, and the per-shot deadline 55→70 s. The code comments say why (“more attempts, not a looser assert”), which is acceptable. The shot now shows the RECYCLE + CHAIN ×3 banner and the +800 pip.
*Caveat:* the `recycle` stage is a scripted showcase. It hard-codes `combo: 3`, `points: 800` and the “CHAIN ×3” text, so it proves the VFX exist, not that real play produces a 3-chain.

## 3. Fun, frame by frame (`gameplay-demo.mp4`, 36.5 s, 2622 frames, VFR avg 71.8 fps)

**What improved (measured):**
- **Recycle feedback:** ghosts now suck 0.5 s into four visible, color-coded chutes (M / P / G / Pa) on the right rail. White “+N” pips rise 48 pt over 0.55 s. Shake now fires on **every** recycle (10 pt, ×1.35 on combo ≥ 2) instead of only at combo ≥ 3. Hit-stop is 60 / 120 ms. Particles are 10–28 per recycle and 30–60 on a 3-chain, plus magenta sparks on chains. Banners are uppercase RECYCLE / CHAIN ×N.
- **Sound:** recycle is 0.48 s, combo 0.42 s and crush 0.55 s (were 0.18 / 0.10 / 0.35), peaking at −2.8 dBFS. Pitch rises with chain length.
- **Cadence:** recycle, press slam or order banners appear about every 1–2 s across 5–36 s. Score goes 900 → 19,342. Level 1→2→3 at about 11 s, 20 s and 28 s.

**What hurts fun (measured):**
- **The board is unreadable (P0-1).** At the identical state (score 4,890, contact sheet panel 3), 54cf2ce filled every occupied cell. 286bb13 draws each locked cell as a **whole-item silhouette shrunk into one cell**. A 1×3 plank becomes three mini planks, and a 3-cell bent pipe becomes three tiny L's. Sprites are 4–7 flat colors with 40–85% transparent area per tile. You cannot see gaps, column heights or cluster membership. 2×2 items (crate, tire) left partial after a recycle or press are still drawn at **2×2 span** from a single cell, so crates overlap neighbours. Board SSIM vs the reference is 0.818 and edge IoU 0.80, but almost all of that structure is the shared bin frame. Inside the stack, the occupied-cell fill dropped visibly (overlay `02-gameplay`).
- **Piece art ignores rotation (P0-2).** `CompactorScene` builds the active piece as **one sprite stretched to the footprint's bounding box**, with no `zRotation`. The bent pipe has 4 rotations, but the L silhouette never changes. Bottle and plank switch between 1×2 and 2×1 / 1×3 and 3×1 by **squashing** the same sprite. The player sees a shape that is not the collision shape, which is a fairness bug in a placement puzzle.
- **Recycle ghost is a flat colored square.** Frames 5.98–6.22 s and 24.03–24.21 s show solid magenta or steel squares fading in place. The ghost reads `existing.texture` after `syncBoard` has already cleared it, so it falls back to `fallbackColor`. It reads as a glitch, not a reward.
- **No tension or curve on screen.** In the 1 s strip (panel 6), the autoplay bin never rises above ~3 rows, and no near-miss state, lip glow or game-over appears. The difficulty curve can't be judged from this evidence. The demo needs a scripted near-miss and a real game-over → “ONE MORE?” beat.
- **Demo audio is fake.** `simulator_smoke.sh` muxes music and SFX at **hard-coded offsets** (`adelay` 2.5 s … 46 s), not when events happen. The audio track proves the files exist, not sound sync. Don't use this video as an App Store preview.
- **Music is still a thin 8 s loop.** Haptics are wired (lock / recycle / clear / tap) but can't be verified from a simulator capture.

**Fun grade: 4.5 / 10 (flat).** The juice gain (+) is cancelled by readability and rotation (−). A “jewel crusher” player decides in the first 10 seconds whether the board is satisfying to read and clear. Right now it reads as scattered stickers.

## 4. Rules
| Rule | Result | Evidence |
|---|---|---|
| No purchase popup at launch / mid-run / after loss | **Pass** | No purchase UI in launch, game or game-over paths. The revive sheet says “No purchase prompts here.” Shop prices are grayed out with “Purchases unlock when ASC product IDs land”. `maybeShowInterstitial` is a stub. |
| Odds shown on random rewards | **FAIL (P0-4)** | Crate screen says **“Bonus Gems 18%”**, but `PlayerProfile.openCrate()` uses `Int.random(in: 0...2)`, so P(gems > 0) = **66.7%**. The scrap range (40–80) is not shown. Displayed odds must match the code (App Store 3.1.1, and our own rule). |
| No “Tetris” anywhere | **Partial (P2)** | Not in any app UI, asset or identifier. It still appears in 4 repo files that *forbid* it: `AGENTS.md`, `docs/DESIGN.md`, `docs/VIBEGAMEDEV_METHODS.md`, and `GameCoreTests.swift:121` (`contains("tetris")`). It was the same in 54cf2ce. Rephrase (“the classic falling-block game”) and build the test string from parts. |
| Asset license file, CC0 / CC-BY / original | **Present; provenance unverified (P1)** | `docs/LICENSES.md` lists everything as Original (Cinder and Crown) with no CC-BY entries. The raccoon, alley and junkyard rasters came in with `fbf0acb` (“neon art”) with no record of how they were made. If they're generator output, record the tool and its ownership terms. The file's own policy says “Do not ship generative art of unknown license.” Junk has 4 duplicate files under alias names (identical md5 pairs bag / bentPipe, box / fridge, plank / scrap, bottle / tube), so drop the legacy copies. |

---

## Ranked fix list

### P0 (blocks TestFlight)
1. **P0-1 Board readability.** Locked cells must fill their cell: either a material-colored cell tile with the item's slice, or one sprite per placed item drawn over its footprint (as crate and tire tried). Never shrink a whole item into each cell. Partial 2×2 items fall back to 1×1 tiles. *Metric:* occupied cells ≥ 85% filled (alpha > 0.5) in the 02-gameplay crop, and SSIM of the stack region vs the 54cf2ce reference stack ≥ 0.6.
2. **P0-2 Active-piece art must match its collision shape in every rotation.** Draw per-cell segments (cap / middle / elbow pieces), or rotate the sprite with `zRotation` for symmetric shapes. *Test:* for each JunkDef rotation, the rendered alpha mask IoU vs the footprint is ≥ 0.8.
3. **P0-3 Launch < 1.5 s, measured honestly.** Add in-app uptime stamps (process start → first title or game frame). Gate smoke on that value at ≤ 1.5 s and restore the wall-clock ceiling to ≤ 8 s. Make `assert_app_frame` reject the splash. Find the main-thread stall (Instruments App Launch template). Fix the clipped 1x-only launch logo.
4. **P0-4 Crate odds must match code.** Either show “Scrap 40–80 (100%) · Gems: 0 (33%) / 1 (33%) / 2 (33%)” or change the roll to match 18%. Add a unit test that pins the displayed odds to the roll table.

### P1 (fix before a useful playtest)
1. Recycle ghost: snapshot the texture **before** clearing cells, so the suck shows the real item, not a flat square.
2. Raccoon matte: give the body an opaque interior (Idle is 5.9% opaque) and remove the stair-step checker remnants. Add an interior-opacity test.
3. Prompt stacking after loss: don't fire ATT / UMP + the notification prompt on the first game-over. Move ATT and UMP to the first opt-in rewarded-ad tap or the first Shop visit. Ask for notifications on a win or streak screen, never at game-over. Make sure cold launches with `firstWin` don't run UMP / GAD work inside the launch window.
4. Demo evidence: add a scripted near-miss and a real game-over → ONE MORE? beat. Capture real in-app audio (or drop the fake mux and label the video silent). Capture the real title frame.
5. Art provenance: record how each raster was made in `LICENSES.md`, and delete the 4 duplicate legacy junk files.
6. Music: replace the 8 s loops with ≥ 60 s beds (ElevenLabs is approved) and add a near-miss tension layer.

### P2 (polish)
1. Make the icon's raccoon face ~50% of the canvas and pull the neon border inside the corner mask.
2. Scrub the forbidden word from docs and tests.
3. Fix the mislabeled `00-springboard-icon-crop.png` (it's the full frame when Pillow is missing).
4. Chute labels are 9 pt (“M / P / G”). Raise to ≥ 11 pt or use icons.

---

## Measured appendix
| Metric | 54cf2ce | 286bb13 |
|---|---|---|
| App icon unique colors | 2 | ~7,738 (sampled), RGB, no alpha |
| Raccoon transparent px | 0 | 146,828–152,559 |
| Raccoon opaque px (Idle) | 262,144 | 15,445 |
| Splash hold in demo | 4.75 s | 3.5 s (1.257→4.752) |
| Tap → first meaningful frame | ~5.7 s | **~3.9 s** |
| Smoke launch value / gate | n/a / 8 s | 16 s / **45 s** |
| Demo duration / frames / avg fps | 37.09 s / 2335 / 63.0 | 36.50 s / 2622 / 71.8 |
| Packet gaps > 50 ms | 33 (max 2173 ms) | 25 total, 19 in play (max 180 ms) |
| Demo audio | none | 1 AAC track, synthetic offsets |
| Score start → end | 900 → 19,835 | 900 → 19,342 |
| recycleSuck / hitStop short / combo | 0.25 / 0.04 / 0.09 s | 0.50 / 0.06 / 0.12 s |
| Shake recycle / press | 6 / 12 pt (combo ≥ 3 only) | 10 / 16 pt (every recycle) |
| SFX recycle / combo / crush | 0.18 / 0.10 / 0.35 s | 0.48 / 0.42 / 0.55 s |
| Crate odds shown vs actual | none shown | 18% shown vs 66.7% actual |

SSIM vs fixed 54cf2ce references (402×874, gray): title 0.305 (splash captured instead), gameplay 0.818, compactor 0.518, recycle 0.524, revive 0.689, base 0.981, pass 0.976, shop 0.651, notification 0.936, daily 0.808, share 0.988, streak 0.954. Full table with edge IoU and palette ΔE is in `diff_286bb13_vs_54cf2ce.json`.

Not verified: physical-device install, haptics, real audio sync, and the interactive FTUE (skipped in smoke). Video-based shake magnitude was inconclusive (rail tracking picks up other magenta UI), so shake values above are from `feel.json` and code.
