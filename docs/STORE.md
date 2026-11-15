# Trash Stack — Store readiness

Publisher: **Cinder and Crown LLC**  
Owner / App Store tester: Nicholas (`nawill@mac.com`)  
Home-screen display name: **Trash Stack**  
App Store listing name: **Trash Stack: Neon Junk Puzzle**  
Bundle ID: `com.cinderandcrown.trashstack`  
App Store Connect Apple ID: **6834995780**  
Version: **1.0.0**  
Web: https://trash-stack.pages.dev/

> Never use the trademarked name of the famous Soviet falling-block franchise (or the word for its seven one-sided pieces) in listing copy, keywords, screenshots text, UI, or docs destined for store review.

---

## App Store (iOS)

### Listing copy

**Name:** Trash Stack: Neon Junk Puzzle  
**Subtitle (30):** Crush junk in a neon dumpster  

**Promo text (170):**  
Night shift at the docks. Drop cans, tires, and neon tubes into the 8×15 compactor, crush full rows, recycle matching materials, and let Trash Panda magnet-steal a piece. Free with optional ads — no paid loot.

**Description:**

Trash Stack is a neon steam-punk junk puzzle from Cinder and Crown — the same Trash Panda raccoon universe as our other game. You are on night shift at the docks. Drop crushed cans, pizza boxes, tires, bags, pipe sections, and neon tubes into an **8×15 dumpster / compactor bin** (not a plain well). Full rows get crushed by a hydraulic press for scrap points. Match three or more same-material tiles (metal, plastic, paper, glass) for a recycle pop. Charge the Magnet and Trash Panda steals a falling piece into your stash bin.

Free to play with optional rewarded ads and IAP (Neon Gems, Season Pass, Remove Ads). Soft currency **Scrap** is earned in play; **Neon Gems** are premium. Unlock looks, build a Junkyard hideout, open run-earned crates (odds always shown). No accounts, no cash-out, no real-money gambling. Crates are never sold for cash without odds.

- Portrait, one-hand friendly controls (tap, swipe, pads) with DAS, ARR, and lock delay
- Compactor clears, recycle combos, Magnet power-up, Trash Panda mascot reactions
- Daily spin, tonight’s hustle challenges, achievements, Night Pass track
- Haptics, juice, and original tiny synth beeps (no franchise theme music)
- Progress saved on your device

Crush clean. Stay neon. Don’t drop the trash.

**Keywords (100 chars max, comma-separated):**  
`puzzle,junk,neon,arcade,compactor,casual,offline,raccoon,recycle,dumpster`

**Category:** Games → Puzzle  
**Secondary (optional):** Games → Family  

**Support URL:** https://trash-stack.pages.dev/support.html  
**Privacy Policy URL:** https://trash-stack.pages.dev/privacy.html  
**Marketing URL (optional):** https://trash-stack.pages.dev/

### Age rating questionnaire (target ≤12+)

Answer **No** / none / not present for:

| Topic | Answer |
|-------|--------|
| Cartoon or fantasy violence | No |
| Realistic violence | No |
| Profanity or crude humor | No |
| Horror / fear themes | No |
| Mature / suggestive content | No |
| Alcohol, tobacco, or drug use | No |
| Simulated gambling | No (spin uses soft currency / rewarded ads only; odds shown) |
| Medical / treatment information | No |
| Unrestricted web access | No |
| Gambling and contests | No |
| Contests | No |

Casual abstract neon puzzle with cosmetics, ads, and optional IAP. Expected rating: **12+** max (Infrequent/Mild Simulated Gambling for lucky spin + crates with odds disclosed; no real-money gambling). Prefer **9+** / **12+** questionnaire answers — never 17+.

### Privacy nutrition labels (App Store Connect)

With AdMob (free + ads):

| Data type | Linked to identity | Used for tracking | Purpose |
|-----------|--------------------|-------------------|---------|
| Device ID | No | Yes (if ATT allowed) | Third-party advertising |
| Advertising Data | No | Yes (if ATT allowed) | Third-party advertising |
| Product Interaction (optional) | No | No | App functionality (on-device scores/prefs — declare only if ASC requires; we do not upload progress) |

- Progress / scores stay on-device (UserDefaults / Preferences) — not collected by Cinder and Crown servers
- **ATT flow:** `NSUserTrackingUsageDescription` → AdMob `requestTrackingAuthorization` before personalized ads
- **UMP / GDPR:** AdMob consent form when required
- `PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1) + Device ID + Advertising Data for AdMob; `NSPrivacyTracking` as appropriate for ATT
- `ITSAppUsesNonExemptEncryption` = **false**

### Play Data safety (Android — later)

Declare AdMob advertising ID / ad interaction as collected by Google for advertising. App does not share data with other third parties beyond the ad SDK. No account data.

### Screenshot plan (6.9" + 6.5")

CI artifact **`app-store-review-evidence`** includes simulator captures + demo video:

| Slot | Caption idea | Content |
|------|----------------|---------|
| 1 | Neon junk. Night shift. | Title — logo, Scrap/Gems, Play, hustles |
| 2 | Crush it in the compactor | Gameplay — 8×15 dumpster, junk objects, mascot |
| 3 | Spend Scrap, not cash | Shop — skins / trails |
| 4 | Tonight’s hustle | Challenges on title |
| 5 | Flex the dock badges | Achievements |
| 6 | Your bin, your rules | Settings — sound, privacy, support |

### Demo video (CI)

- Artifact file: `artifacts/video/gameplay-demo.mp4` (also copied into screenshots folder)
- Target length: **45–60 seconds** on iPhone 16 Pro Max simulator
- Shows: compactor clear, recycle combo, Magnet power-up, game over, rewarded revive prompt (test ads), level-up, shop

### TestFlight CI

- Push a tag matching `testflight/*` (for example `testflight/1.0.0-1`) to archive, sign with the App Store Connect API key, and upload.
- PR / branch runs **build + validate only** (simulator build + screenshots + demo video). They do **not** archive or upload to TestFlight.
- Required GitHub secrets: `APPLE_TEAM_ID`, `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`.
- Do **not** push TestFlight tags from agents — Fire Fox owns tagging.
- Agents do **not** submit to App Store Connect for review.

### What’s left for App Store submission

1. Confirm GitHub secrets for ASC API signing are set.
2. Have Fire Fox push `testflight/1.0.0-N` after CI is green on the merge.
3. In App Store Connect (app 6834995780): update listing name to **Trash Stack: Neon Junk Puzzle**, paste copy above, attach CI screenshots, set age rating, privacy nutrition labels for AdMob, category Puzzle.
4. Replace Google TEST AdMob unit IDs with production IDs before the store build.
5. Add Nicholas (`nawill@mac.com`) as a TestFlight internal tester if not already.
6. Wire Remove Ads / Premium Pass StoreKit products when ready (stubs until then).
7. Submit 1.0.0 for review after a good TestFlight build — **not** by this agent.

---

## Google Play (Android — ready next)

### Package

- Application ID: `com.cinderandcrown.trashstack`
- Version name: `1.0.0` / versionCode starts at `1`
- `targetSdk` / `compileSdk`: **36**
- CI produces a **signed AAB** when keystore secrets exist; otherwise debug APK only.

### What you need for Play

1. Google Play developer account for Cinder and Crown LLC.
2. Upload keystore secrets (`ANDROID_KEYSTORE_BASE64`, passwords, alias).
3. Create the Play Console app (title can mirror **Trash Stack: Neon Junk Puzzle**).
4. Data safety: AdMob advertising ID / ad interaction.
5. Privacy / support URLs same as iOS.

---

## Distinct identity (trade-dress distance)

We intentionally diverge from look-and-feel claims around the famous falling-block franchise (see e.g. the 2012 holding that protected playfield look-and-feel elements of that game):

| Ours | Not ours |
|------|----------|
| **8×15** dumpster / compactor bin with pipes, grates, hydraulic press | 10×20 plain matrix well |
| Junk **triomino + pentomino** set drawn as cans, boxes, tires, bags, pipes, tubes | Classic seven one-sided brick pieces in stock colors |
| Compactor crush + material recycle matching + Magnet / Trash Panda | Ghost-piece silhouette + hold slot + line-clear “vanish” only |
| Stash bin + conveyor + scrap-dust drop guide (no classic ghost outline) | Uniform single-color bricks + ghost outline |
| Original neon synth beeps | Franchise theme music / soundfonts |
| Trash Panda cross-promo mascot | Competitor branding |

Random rewards are soft-currency or rewarded-ad only; odds are disclosed. No real-money gambling or paid loot boxes.

---

## Monetization (free + ads)

- **Rewarded video (opt-in):** revive once per run, double Scrap after a run, extra daily spin, chest speedup
- **Interstitials:** between runs only; never first 2 runs of a session; at most one every 3 game overs; **no banners during play**
- **Remove Ads** — one-time IAP stub (disabled; StoreKit/Play Billing TODO, no product IDs yet)
- **Premium Pass / Night Pass premium lane** — stub only
- Ad units default to **Google official TEST IDs**; real IDs via `web/ad-config.js` + native app ID strings
- ATT + UMP on iOS; PrivacyInfo + privacy.html document advertising data collection


See **docs/ECONOMY.md** for Scrap/Gems tuning, Junkyard, Season Pass, crates, and compliance tables.
