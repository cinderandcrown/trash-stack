# Trash Stack QA — commit `54cf2ce`

**Game:** Trash Stack (Recycling Night Shift), repo `cinderandcrown/trash-stack`, PR #2, branch `cursor/trash-stack-native-swift-497e`  
**Commit:** `54cf2ce07003ca327ef7cc9a5e04e6b3fbb72e01` (“Docs: allow mild pay-to-win, keep no-nagging”)  
**Reviewer:** Fire Fox, measured-art-qa pass (overlays / scores / frame timing, not eyeballing alone)  
**Date:** 16 Nov 2026, America/Chicago  
**Contact sheet:** `docs/qa/CONTACT_SHEET_54cf2ce.png`  
**Scores JSON:** `docs/qa/scores_54cf2ce.json`

---

## Verdict

**NO — do not send this commit to TestFlight for Nicholas to play.**

The drop / recycle / press loop is real and the 37-second simulator demo plays through to a 19,835 score, but the first things he would see are a **plain cyan-square app icon** and a **raccoon mascot sitting on a baked-in checkerboard**. Those two defects would color the whole playtest. Fun is not yet in the same league as a top match-3 or puzzle-strategy hit: cascades exist in code, but the juice is brief and quiet, materials are hard to read, Shift Mode is a label on Endless, and several retention screens are still facades.

**Fix the P0s (icon, raccoon alpha, and the ~5 second cold-launch stall), then this is worth an internal TestFlight.** The core loop is far enough along that his feel notes would be useful — just not on a build that looks unfinished on the home screen and the title page.

**Overall score: 5.1 / 10** (fun weighted heaviest, ~40% of the grade).

| Category | Score | Notes |
|---|---:|---|
| Fun (heaviest) | 4.5 | Chains, a player-timed press, and order tickets are in. Celebrations, readable junk, and “one more run” tension are not at a top-chart bar. |
| Feel / juice | 4.0 | 0.25s chute suck, 6–12 px shake, 40–90 ms hit-stop, 0.18s recycle SFX, 8s thin music loop. Toasts say “Recycled” in small type. |
| Readability | 4.5 | Order tickets contrast 10.1:1; PLAY is 46 pt. Junk is opaque squares; paper planks look like green PCBs; bent pipes use a purple “bag” tile. |
| Onboarding / first 60s | 4.0 | Text-only four-card intro, not a guided first chain. Cold start holds the launch logo ~5s in the demo. |
| Retention hooks | 6.0 | Streak, Daily Dumpster, share card, Season Pass, Junkyard, and crates are on screen. Shift levels, quests, shop buys, and crate loot reveals are not truly wired. |
| Monetization ethics | 7.5 | No-nag rules are in config and unit-tested. Revive is an opt-in rewarded ad. Shop IAP is display-only (cannot accidentally charge). Name “Night Shift Crate” on a $19.99 gem pack is risky. |
| Performance | 6.0 | In-play packet timing is near 60 fps with 50–180 ms gaps (some are designed hit-stop). Launch stall is the real hitch. Demo has no audio track. |
| Distinct vs. falling-block classics | 6.5 | 8×14 bin, 4+ material clusters (not full-row clears), max straight span 3, named junk, player-timed press. On screen it still reads as colored squares falling in a well. |
| App Store readiness | 3.0 | Unshippable icon, no asset license file, Google test ad IDs, IAP stubs, incomplete privacy manifest. |

---

## Does this build install and play end to end?

**On the iOS 27 simulator, yes for the core loop. On a physical iPhone, this review did not install the build.** Evidence is the green PR CI run `43788946315` (artifact `app-store-review-evidence`) plus the source.

What the 37.1s `gameplay-demo.mp4` actually shows:

- t = 0.0–1.5s — Springboard, with the cyan-square **Trash Stack** icon visible.
- t = 1.8–6.7s — Launch logo held for **~4.75s** (max packet gap 2173 ms). This is a real cold-start stall, likely Ads / ATT / UMP work in `AdsBootstrap.start()` before first paint.
- t ≈ 6.8–36.5s — Autoplay Endless: pieces fall, “Recycled” and “Press slam” toasts appear, the press plate comes down, score goes **900 → 19,835**. The loop works.

Smoke also captured title, gameplay, press, recycle, game-over revive, Junkyard, Season Pass, shop, notification prompt, Daily Dumpster, share card, and streak — 12/12 shots on the PR run. Unit tests in GameCore (board size, recycle-of-4, press, snatch, economy odds, no-nag caps, preview queue, max span 3) passed on both the PR and the failed push run.

What is **not** end-to-end yet:

- Gem Shop prices are decorative `Text` — no `Product.purchase` / `StoreKitService` tap handler.
- Title / Quests “Open Crate” calls `openCrate()` and **discards the loot** (`_ = loot`) with no odds sheet and no reward ceremony.
- Quests are hardcoded strings with no progress wiring.
- Shift Mode writes a level id to `UserDefaults` but `GameEngine.seedOrders` always plants the same three generic tickets. Catalog star goals (“Finish under 40 drops”, “Survive battery hazard”, …) are map copy only.
- Ads use Google **test** unit IDs. `AdsService.showRewarded` in Services returns `true` without showing an ad (app target starts GAD, but still with the test app id).
- I did not run the build on Nicholas’s iPhone.

---

## Push CI failure (`43788943943`) — why, and does it matter?

**Same commit as the green PR runs.** Event is `push` (commit message “Docs: allow mild pay-to-win, keep no-nagging”). `GameCore (Linux)` and `Scripts` passed. `Build and test (iPhone)` compiled and ran 10 unit tests with 0 failures, then `scripts/simulator_smoke.sh` died here:

```
Failed to capture a valid app frame for mode='recycle' → smoke-artifacts/04-recycle-combo.png
exit code 1
```

The push artifact contains only `01-title.png`, `02-gameplay.png`, and `03-compactor-clear.png`. The PR run of the same SHA captured `04-recycle-combo.png` plus marketing shots and the 37s video. Frame-assert logs on the shots that did land are normal (`Frame OK … dark=5–7`).

**This is a flaky capture / deadline issue, not a product regression.** `launch_shot` allows 2 attempts and a 55s per-shot deadline; the recycle staging VFX lasts only 0.25s, so a late screenshot looks like an empty board (which is what even the *successful* 04 shot shows — toast only, juice already gone). SSIM of the shared frames (push-fail vs PR) is 0.976 (title) and 0.895 (compactor); gameplay is 0.610 because the staged board is not deterministic frame-for-frame.

**It matters for CI hygiene, not for “is the game broken.”** Do not loosen `assert_app_frame` to get push CI green. Fix recycle-shot timing (capture mid-suck, or keep the glow up longer) and/or give `recycle` more settle / a third attempt. The green PR CI is the authoritative evidence for this SHA.

---

## P0 — blocks a TestFlight that Nicholas should play

### P0-1. App icon is a cyan square on navy (2 colors)

**Evidence:** `TrashStack/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` is 1024×1024, **2 unique colors**: 62.99% `(7,7,15)` and 37.01% `(0,245,255)` in a centered square. Confirmed on the simulator Springboard in `gameplay-demo.mp4` at t=0–1.5s. See contact sheet callout.

**Fix:** Paint a 1024×1024 icon from the existing launch mark (neon dumpster + wordmark) or a cut-out raccoon on a dark alley, no alpha on the final icon, and replace the app icon set. Re-run smoke and attach a Springboard crop so this cannot regress.

### P0-2. Raccoon art has a baked-in checkerboard (zero alpha)

**Evidence:** `RaccoonIdle.png`, `RaccoonCheer.png`, and `RaccoonPanic.png` are 512×512 RGBA with **0 transparent pixels, 262,144 opaque**. The checkerboard is in the file, not a SwiftUI compositing bug. It shows on the title screen, the revive sheet, the notification prompt, the streak ceremony, and the pass preview — the first and last screens of a session.

**Fix:** Re-export (or flood-fill + mask) true alpha. Corners must be 0-alpha; keep the neon puddle/glow as premultiplied partial alpha. Add a unit or smoke check: raccoon assets must have `transparent > 0` and no mid-gray checker pattern in the corners. Composite them on the alley, not on a black card.

### P0-3. Cold launch holds the splash for ~5 seconds

**Evidence:** Demo packet timing, motion energy, and the frame strip. After Springboard, the launch logo is frozen from **t ≈ 1.8s to 6.7s** (4.75s still stretch, motion < 0.05; max gap 2173 ms). Gameplay then jumps in already at score 900. `AdsBootstrap.start()` requests ATT, then UMP, then `GADMobileAds.start` **before** first interactive frame (`TrashStack/AdsBootstrap.swift`).

**Fix:** Show title (or a real loading bar) immediately. Defer ATT / UMP / GAD until after first paint, and preferably until after the first win or first Shop/ad interaction — ATT at launch also fights the “no prompts at launch” rule in spirit. Budget: first interactive frame < 1.5s on a cold sim; add a smoke assertion on launch-logo duration in the demo video.

---

## P1 — should be fixed before a useful playtest / before store work proceeds

### P1-1. Recycle / cascade juice is too small for the fantasy

**Evidence:** `feel.json` sets `recycleSuckSec: 0.25`, `shakeRecycle: 6`, `hitStopShortSec: 0.04`, `hitStopComboSec: 0.09`. Suck target is an off-screen point at 92% width (`CompactorScene.recycleSuck`) — marketing shot M3 shows only a tiny spark leaving the right edge. Screen shake and the bigger hit-stop fire only when `combo >= 3`. Toasts are a 13 pt “Recycle chain” / “Recycled” label (contrast is actually excellent at 15.5:1, but the type is tiny). `recycle.wav` is 0.18s, `combo.wav` is 0.10s, both 22 kHz mono. The successful 04 smoke shot missed the VFX entirely.

**Fix (this is also Fun change #1):** Visible per-material chutes on the bin; 0.4–0.6s suck; flying score pips; a big stacked banner (RECYCLE → CHAIN x2 → CHAIN x3) that scales with chain length; flash + shake on every recycle, escalating; particles in the 30–60 range on big chains; pitch already scales (`1.0 + combo * 0.1`) — keep it and give the SFX more body (0.4s+). Hold the smoke recycle pose until the glow is visible.

### P1-2. Junk does not read as items or as materials

**Evidence:** All eight `Resources/Junk/*.png` are 256×256 with **0 fully transparent pixels**. They are rounded-rect tiles, so a 1×2 bottle is two identical jars and a 1×3 plank is three PCBs. Texture mapping is wrong for several ids (`JunkPiece.swift` / `docs/ART.md`): `bentPipe` → `bag.png` (purple battery pack, but the material is metal); `fridge` → `box.png` (cardboard, but the material is metal / plastic); `plank` → `scrap.png` (green circuit board, but the material is paper). Crate and tire already render as a single 2×2 object; everything else does not.

**Fix:** Cut real silhouettes (alpha in the corners). One sprite per item, scaled across its cells (extend the crate/tire path). Lock a material language and keep it: metal = cool gray / steel, plastic = magenta, glass = translucent cyan, paper = kraft / cardboard. Remap `bentPipe`, `fridge`, and `plank` art. Add a smoke check that a material legend (or hue clustering on the board) is separable.

### P1-3. First 60 seconds teach with text, not with a guaranteed first chain

**Evidence:** `TutorialView.swift` is four “Got it / Next” cards (Move, Rotate, Cluster, Press). Mode select routes here when `tutorialDone == false`, then jumps into a live game. There is no scripted board, no finger cue, no forced first recycle. First-run onboarding is the weakest path to “this is a lot of fun.”

**Fix:** A 30–45s interactive intro shift: a pre-built almost-cluster the player can complete, a press meter that fills in one or two placements, and a short raccoon bark. Keep Skip. Cards can stay as a pause overlay, not the lesson itself.

### P1-4. Shift Mode is a label, not handcrafted levels

**Evidence:** `ShiftCatalog` has six named levels with star goals, and `ShiftMapView` unlocks them. `GameEngine.seedOrders(level:)` always plants “Recycle 20 {material}”, “Make a 3× chain”, “Slam the press”. Nothing reads `trashStack.shiftLevel` or `starGoals`. `profile.shiftProgress = max(profile.shiftProgress, profile.shiftProgress + 1)` is just `+= 1` when all generic orders are done. The mode card promises “Handcrafted districts · order tickets · 3-star goals.”

**Fix:** Load each level’s star goals as the run tickets, seed a distinct opening board, and actually gate the advertised hazards. Until that ships, do not market Shift as handcrafted — or hide the mode.

### P1-5. Retention ceremonies and shop are facades

**Evidence:**

- Streak smoke is forced in `RootView.applyShotMode`: `max(r.scrap, 48)` and `max(r.gems, 1)`, or `(3, 48, 1)` if already claimed. Real math is `StreakRewards.scrap(1) = 18` and `gems(1) = 0`. The 12-streak screenshot is not the day-1 reward.
- `openCrate()` return value is discarded on Title and Quests; no odds line is shown at open time, despite the title footer “odds shown.”
- `ShopView` lists prices as `Text` with no purchase action. The starter-pack card has “Not now” and no buy button. Pack title **“Night Shift Crate”** at $19.99 is a gem pack, which is a Guideline 3.1.1 look-alike risk.
- `QuestsView` is static copy.
- Junkyard is a single painting plus a list; every building in the smoke is “Level 1 · ~82s remaining.” The yard does not visually upgrade.

**Fix:** Show the real streak numbers in CI (stop forcing 48/1). On crate open, present the loot and the `%` table. Wire StoreKit 2 purchases on the price capsules, or disable them until products exist; rename the $19.99 pack so it does not say “Crate.” Hook quest progress. Make at least one yard building change the hero image when upgraded.

### P1-6. No asset license file; provenance of AI-looking art is undocumented

**Evidence:** Intended design requires in-game art to be CC0 / CC-BY or original, with a license file. `NOTICE` is only a copyright line. `docs/ART.md` and `docs/ASSET_MANIFEST.md` say “Licenses: see docs/ART.md” and never list sources. The raccoon and alley / junkyard paintings are typical generative stills; junk tiles look original/simple. This is a store and a standing-rules issue.

**Fix:** Add `docs/LICENSES.md` (or extend NOTICE) naming every raster, font, and wav: source, license, author, URL. Replace anything that cannot be documented. Do not ship without this.

### P1-7. Store / ads / privacy are still test stubs

**Evidence:** `Info.plist` `GADApplicationIdentifier` and `AdsService` use `ca-app-pub-3940256099942544~1458002511` (Google’s test app id). `NSPrivacyTracking` is `true` with an **empty** `NSPrivacyTrackingDomains` array. `StoreKitService` loads product ids and `stubPurchase` only inserts into a set. `Configuration.storekit` exists, but the shop UI does not call it. Version is `1.0.0` (1). Only one SKAdNetwork id is listed.

**Fix:** Production AdMob app id and units (ask before spending). Fill the privacy manifest (and only set tracking true if ATT is actually used). Implement `Product.purchase` + entitlements. Register IAP in App Store Connect when Nicholas approves. Fine for a later playtest to still use StoreKit configuration / test ads, but not for submission.

### P1-8. Demo video has no audio; music/SFX are unproven in CI

**Evidence:** `ffprobe` on `gameplay-demo.mp4` — one H.264 video stream, **zero audio streams**, 90.5 MB, 37.1s. DESIGN asks for a video with music + SFX. Wavs exist (`game_loop.wav` / `menu_loop.wav` are 8.0s at 10% RMS; `crush.wav` is 0.35s). Near-miss “tension” just retriggers `game_loop` and plays `ui` / `lock` at 0.45–0.55 pitch (`GameContainerView.syncHUD`).

**Fix:** Record demo audio (simctl / in-app tap). Add a near-miss bed or a real filter on the loop. Loudness-match SFX so a crush and a 3-chain are obviously bigger than a single recycle.

---

## P2 — polish

- Title wordmark is `system(size: 40, weight: .black, design: .rounded)` with a gradient (contrast 4.47:1, just under 4.5:1 for small text). A custom mark would match the Bandit logo direction; not a playtest blocker.
- “BIN ALMOST FULL” is still showing on the overflow / game-over shot. Use “BIN OVERFLOW” / “SHIFT OVER” when `state.over`.
- Recycle-chain order only bumps when `chain >= 3`, so a 2-chain does not count as progress toward a 3-chain ticket — confusing.
- Daily share card always awards at least one star: `stars = min(3, max(1, orders.done))`.
- Season Pass tiers are identical cyan circles; no cosmetic preview art.
- Marketing captions cover PRESS / SNATCH.
- `ECONOMY.md` still mentions `index.js`, `npm test`, and CSS — leftover from the Capacitor path; Pass price is $4.99 in one table and $9.99 / 450 gems in another.
- Interstitials may fire in `finalizeOver` after clock-out (capped, opt-out via Remove Ads). Keep them off the first sessions; never pair them with a purchase offer.
- Smoke `assert_app_frame` and missing-texture checks have size-only fallbacks (see loosened gates). Do not weaken them further.
- PLAY button height is **46 pt** (meets 44). PRESS / SNATCH are large thumb-safe controls on the screenshots. Keep them clear of the home indicator (already padded).

---

## Loosened / unreliable gates (audit)

None of these made a *failing product test* pass by changing a gameplay assertion, but they do make CI a weaker witness.

1. **`assert_app_frame` size-only fallback** (`scripts/simulator_smoke.sh`): if the PNG cannot be sampled, the script prints `Frame OK … (size-only N bytes)` and **exits 0**.
2. **Missing-texture check** allows a 0.18 bright/red ratio, and falls back to `Junk art size-OK` when Pillow fails.
3. **Springboard detect** is `beiges >= 5 and darks <= 1` (previously `darks == 0`). Minor.
4. **`launch_shot` max_attempts = 2** with a 55s deadline — direct cause of push CI dying on `recycle`. Earlier the cap was 3.
5. **Streak evidence is faked** (`max(r.scrap, 48)`, `max(r.gems, 1)`). A green 12-streak shot does not prove day-1 rewards.
6. **Share-card evidence** uses a repeating canned grid and a forced 2400 / 3-star score.
7. **`testShotScenariosAreDistinct`** only requires the board to be **> 1/8 filled**.
8. **`AdsService.showRewarded` returns `true`** in the Services stub; CI cannot fail a missing ad.
9. **Demo video has no audio**, so the “music + SFX” evidence requirement is unmet even when the workflow is green.
10. **`presentRecycleMoment`** is a staged glow, and the smoke still often photographs the pose *after* the 0.25s suck. A green 04 shot is not proof of visible juice.

Do not loosen any of the above to make a future build pass. Tighten 1, 5, 8, and 9 before trusting CI as store evidence.

---

## Top 5 changes that make it way more fun

Ranked by **impact on fun vs. effort**, benchmarked against the *feel* of top match-3 / puzzle-strategy hits (cascades, combo escalation, crunch, near-miss, one-more-run) without copying their mechanics or art.

1. **Explosive recycle and cascade juice (high impact, medium effort).** This is the gap between “the matcher works” and “I want to hit one more chain.” Visible chutes, longer suck, huge typography that escalates (CHAIN x2 / x3 / x4), score pips, screen pulse on every recycle, fatter SFX already pitched in code, and a press slam with hit-stop + scrap shower that can *set up* a cascade you can see coming. Until this lands, fun cannot crack ~7/10.
2. **Readable silhouettes and a locked material language (high impact, medium effort).** Players cannot plan chains if a paper plank is a green PCB and a metal bent pipe is a purple pack. One object per item (like crate / tire already), honest silhouettes, material colors you can read in the next-queue. This also pulls the game visually away from “colored squares in a well.”
3. **An interactive first shift that gifts a first chain (high impact, medium effort).** A pre-built almost-cluster, a press that comes online quickly, and a raccoon cheer. Top puzzle hits win the first 45 seconds with a guaranteed “oh, that’s satisfying.” Text cards do not.
4. **Near-miss and press-as-risk (high impact, medium-low effort).** Lip glow + a real tension bed when the bin is within 3 rows (the flag already exists: `nearMissRows: 3`). Telegraph which clusters a PRESS will create after the bottom two rows vanish. A hold/stash already exists — teach it as the planning tool for a 3-chain. This is the risk/reward loop the design asked for.
5. **A honest one-more-run ceremony (medium-high impact, medium-low effort).** Game-over should recap the near-miss (“you were one glass cell from a 3-chain”), show streak / Daily progress, and let Revive stay a quiet opt-in ad. Show real crate loot with odds. Make Daily Dumpster a tight, fair, shareable puzzle (the share card is already a good hook). Hide or defer Shift until levels are real so the mode select does not over-promise.

---

## Fastest credible path to App Store submission

Trash Stack is the right title to push first — the loop is smaller than a platformer, and the matcher is already in place — but **this commit is not a submission candidate**. A credible path, in order:

### Must-have before asking Nicholas to submit

- All **P0** items: real app icon, raccoon (and junk) alpha, cold-launch under ~1.5s.
- Fun pass from items 1–3 above, enough that a 3-chain and a PRESS slam feel punchy on a phone. Without this, reviews will say “generic.”
- Interactive FTUE and a truthful mode select (Shift either works or is hidden).
- `docs/LICENSES.md` for every in-game raster, font, and wav (CC0 / CC-BY / original only).
- Production AdMob ids, ATT / UMP only after first paint, a complete privacy manifest, and Privacy Nutrition Labels that match it.
- Real StoreKit 2 purchases for gem packs / Remove Ads / Pass; rename “Night Shift Crate”; odds visible on every random reward; no purchase UI at launch, mid-run, or after a loss (already designed — keep it).
- App Store screenshots and preview filmed from a build whose icon, mascot, and juice match what reviewers will install. Current marketing shots are usable as a base once the raccoon/icon are fixed.
- A physical-device playtest (TestFlight) of the post-P0 build, with Nicholas’s feel notes closed or explicitly deferred.
- His explicit OK before submission (standing rule).

### Can wait for a day-one patch or season 1 update

- Full six-district handcrafted Shift with unique boards and hazard rollout.
- Yard that visually grows (Clash-style come-back fantasy) and real-time timers worth opening the app for.
- Unique Season Pass cosmetic art (bin skins, chute flares, raccoon outfits) — the 100-tier structure can stay.
- Game Center leaderboards / achievements actually registered in App Store Connect (hooks exist).
- Conveyor / magnet districts, leaking-battery juice, a dedicated near-miss music bed, ElevenLabs barks.
- Google Play (already on the back burner).
- Live events, extra IAP cosmetics, a richer album.

**Practical sequencing:** 1–2 days on P0 art + launch, 3–5 days on juice + silhouettes + interactive FTUE, then an internal TestFlight. Parallel-track licenses, AdMob / IAP / privacy so a store submission can follow a good playtest by about a week, not a month — provided the fun pass actually feels good on a phone.

---

## Measured metrics (appendix)

| Metric | Value |
|---|---|
| Screenshot size | 1206×2622 px (3×, 402×874 pt) |
| PLAY button | 232×46 pt (meets 44 pt min) |
| Title tagline contrast | 5.23:1 |
| Title wordmark contrast | 4.47:1 |
| Order-ticket contrast | 10.06:1 |
| Recycle-toast contrast | 15.52:1 |
| RaccoonIdle transparent px | 0 / 262,144 |
| Junk tile transparent px | 0 / 65,536 (all eight) |
| App icon unique colors | 2 (cyan 37.01%, navy 62.99%) |
| Demo duration / fps / frames | 37.09 s / 62.96 avg / 2335 |
| Demo audio streams | 0 |
| Packet gaps > 50 ms | 33 (max 2173 ms, during launch) |
| Launch-logo hold in demo | 4.75 s |
| Autoplay score | 900 → 19,835 |
| Push vs PR SSIM | title 0.976, compactor 0.895, gameplay 0.610 (staged) |
| SFX | 22 050 Hz mono; recycle 0.18s, combo 0.10s, crush 0.35s, loops 8.0s @ ~10% RMS |
| Board | 8×14 visible + 2 hidden; recycle threshold 4; press = bottom 2 rows; press meter 8 |
| Chain score multiplier | `1 + max(0, chain − 1)` (linear) |

References used: the intended Nov 15 2026 redesign (8×14 bin, material clusters, player-timed press, tickets, Snatch, neon identity, no-nag F2P), `docs/DESIGN.md` / `ECONOMY.md` / `ART.md`, and feel of top puzzle-strategy / match-3 hits for *juice only* — no mechanic or art copying, and no classic falling-block names in this report.

Smoke artifacts: `/workspace/trash-stack-ci/pr-ci/app-store-review-evidence/` (authoritative) and `/workspace/trash-stack-ci/push-fail/app-store-review-evidence/` (incomplete, failed at 04).
