# Trash Stack — Store readiness

Publisher: **Cinder and Crown LLC**  
Owner / App Store tester: Nicholas (`nawill@mac.com`)  
Home-screen display name: **Trash Stack**  
App Store listing name: **Trash Stack: Neon Blocks**  
Bundle ID: `com.cinderandcrown.trashstack`  
App Store Connect Apple ID: **6834995780**  
Version: **1.0.0**  
Web: https://trash-stack.pages.dev/

> Never use the word “Tetris” in listing copy, keywords, screenshots text, or code comments destined for store review. It is a trademark of The Tetris Company.

---

## App Store (iOS)

### Listing copy

**Name:** Trash Stack: Neon Blocks  
**Subtitle (30):** Neon night falling-block puzzle  

**Description:**

Trash Stack is a neon night-city falling-block puzzle from Cinder and Crown. Stack glowing pieces in the docks, clear rows, chain combos, and chase Shinies under neon rain.

Play offline on night shift. Unlock raccoon-mask skins and city backgrounds with in-game Shinies — no ads, no accounts, and no real-money shop in 1.0.

- Portrait, one-hand friendly controls (tap, swipe, pads)
- Daily spin and tonight’s hustle challenges
- Haptics, juice, and a soundtrack of tiny synth beeps
- Progress saved on your device

Stack clean. Stay neon. Don’t drop the trash.

**Keywords (100 chars max, comma-separated):**
`puzzle,blocks,neon,arcade,stack,casual,offline,night,combo,raccoon`

**Category:** Games → Puzzle  
**Secondary (optional):** Games → Family  

**Support URL:** https://trash-stack.pages.dev/support.html  
**Privacy Policy URL:** https://trash-stack.pages.dev/privacy.html  
**Marketing URL (optional):** https://trash-stack.pages.dev/

### Age rating (likely 4+)

Answer **No** / none for:

- Cartoon or fantasy violence
- Realistic violence
- Profanity or crude humor
- Horror / fear themes
- Mature / suggestive content
- Alcohol, tobacco, or drug use
- Simulated gambling
- Medical / treatment information
- Unrestricted web access
- Gambling and contests
- Contests

This is a casual abstract puzzle with neon cosmetics. Expected rating: **4+**.

### Privacy nutrition label

**Data Not Collected.**

- No tracking
- No analytics SDKs
- No account
- No ads
- Progress stays on-device (UserDefaults / Preferences)

`ITSAppUsesNonExemptEncryption` = **false** (no custom encryption; no networking for gameplay).

### Screenshot plan

Produce real simulator captures in CI (`artifacts/screenshots`, workflow artifact `app-store-screenshots`):

| Slot | Device class | Content |
|------|----------------|---------|
| 1 | 6.9" (iPhone 16 Pro Max) | Title screen — logo, Shinies, Play |
| 2 | 6.9" | Mid-game well with neon blocks + HUD |
| 3 | 6.5" (iPhone 15 Plus / 11 Pro Max) | Title screen |
| 4 | 6.5" | Mid-game or shop / daily spin |

Manual polish before submit: crop status areas if needed, ensure no competitor marks, prefer dark neon frames matching brand.

### TestFlight CI

- Push a tag matching `testflight/*` (for example `testflight/1.0.0-1`) to archive, sign with the App Store Connect API key, and upload.
- PR / branch runs **build + validate only** (simulator build, screenshots, optional IPA export). They do **not** upload to TestFlight.
- Required GitHub secrets: `APPLE_TEAM_ID`, `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`.
- Do **not** push TestFlight tags from agents — Fire Fox owns tagging.

### What’s left for App Store submission

1. Confirm GitHub secrets for ASC API signing are set on the public repo.
2. Have Fire Fox push `testflight/1.0.0-N` after CI is green on the merge.
3. In App Store Connect (app 6834995780): paste listing copy above, attach CI screenshots, set age rating, privacy = Data Not Collected, category Puzzle.
4. Add Nicholas (`nawill@mac.com`) as a TestFlight internal tester if not already.
5. Submit 1.0.0 for review after a good TestFlight build. Premium Pass stays disabled (no StoreKit).

---

## Google Play (Android — ready next)

### Package

- Application ID: `com.cinderandcrown.trashstack`
- Version name: `1.0.0` / versionCode starts at `1`
- `targetSdk` / `compileSdk`: **36** (current Play requirement for new apps/updates as of late 2026)
- CI produces a **signed AAB** when keystore secrets exist; otherwise debug APK only (clean skip).

### What you need for Play

1. **Google Play developer account** for Cinder and Crown LLC (one-time registration fee).
2. **Upload keystore** (keep the backup safe). Suggested secrets:
   - `ANDROID_KEYSTORE_BASE64` — base64 of the `.jks` / `.keystore`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS`
   - `ANDROID_KEY_PASSWORD`
3. Create the Play Console app (store title can mirror **Trash Stack: Neon Blocks**).
4. Upload the CI `trash-stack-aab` artifact, complete Store listing, content rating questionnaire, Data safety = no data collected, and target audience.
5. Privacy / support URLs same as iOS.

Local signing (optional): place `android/keystore.properties` (gitignored) with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.

---

## Trade-dress risk (The Tetris Company)

We intentionally keep identity distinct:

| Keep | Avoid |
|------|--------|
| Neon raccoon / Trash Stack branding | Soviet-era puzzle branding, “classic blocks” clichés tied to that franchise |
| Our night-docks / alley / subway skins | Competitor logos, music, or soundfonts |
| Own piece colors & cosmetic skins | Using the word “Tetris” anywhere in store or UI |
| “Falling-block puzzle” wording | “Tetrimino”, “matrix”, branded theme packs |

**Still watch:**

- Default seven-piece set geometry is the industry-standard tetromino set (common to many puzzles). Mitigate with raccoon theme, neon trash fantasy, unique HUD, and original naming (Shinies, hustles, docks).
- Playfield is a 10-wide well (genre convention). Do not market as an official or classic clone.
- Avoid red-blue-yellow-green “toy brick” palette that closely mimics famous franchise marketing screenshots; prefer cyan / magenta / gold neon.

If legal review asks for further distance: add a asymmetric “junk” piece set cosmetic as default, and lean harder on raccoon / city copy in screenshots.

---

## Monetization (1.0)

Out of scope. UI shows a disabled **Premium Pass (coming soon)** button only — no StoreKit / Play Billing.
