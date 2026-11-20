# Licenses — Trash Stack assets

Every in-game raster, font, and wav must be **CC0**, **CC-BY** (with attribution), or **original** (Cinder and Crown LLC). Replace anything of unknown provenance before store submission.

## Original (Cinder and Crown LLC, © 2026)

| Asset | Path(s) | Provenance |
|-------|---------|------------|
| App icon | `TrashStack/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | **Higgsfield commercial-cleared original** (Nicholas Will Ultra plan, 20 Nov 2026). Option A — raccoon peeking from a neon dumpster; opaque 1024×1024 RGB, no alpha, no rounded corners. Job `d73752d6-00c7-4ddc-96c1-5b32574bc36c`. Full terms: `docs/art/APPICON_LICENSE.md` |
| Launch logo | `LaunchLogo.imageset` (@3x 600×600) | Original neon card mark; shipped at 3x so launch UIImage is ~200 pt (not clipped) |
| Cinder & Crown mute logo | `CinderCrownMute.imageset` (@1x/@2x/@3x) | **Cinder & Crown logo, © Cinder and Crown LLC, used by permission.** Publisher ident only (phoenix + crown, no wordmark). Source PNG md5 `f4a3ffce2b58ddd4f12c010427782ac8` |
| Ident SFX | `ember_whoosh.wav` | Original procedural ember/whoosh; respects mute |
| The Bandit — mood heads + title hero | `RaccoonIdle`←`head-idle`, `RaccoonCheer`←`head-cheer`, `RaccoonPanic`←`head-panic`, `RaccoonGameOver`←`head-gameover`, `BanditHero`←`hero-front` | **Higgsfield commercial-cleared original** (Nicholas Will Ultra plan, 20 Nov 2026). Shared cyberpunk raccoon with *The Neon City Bandit* (goggles, black hoodie with magenta trim, brass harness, cyan cables). Full terms: `docs/art/BANDIT_LICENSE.md`. Pack: `docs/art/bandit-shared/`. Animated loops + bandit dumpster AppIcon incoming — keep current dumpster icon until then. |
| In-game art pack (bin / tiles / slam / clear) | `BinInterior`, `can`/`glass`/`plastic`/`cardboard`/`pizza`/`banana`/`tire`, `Slam01`/`Slam02`, `ClearBurst`, `CellPlate` | **Higgsfield commercial-cleared original** (Nicholas Will Ultra plan, 20 Nov 2026), style-matched to dumpster AppIcon. Full terms: `docs/art/TS_ART_LICENSE.md`. Archive: `docs/art/ts-art/` (cute raccoon poses not shipped). |
| Recycle ghost plates | `GhostMetal`, `GhostPlastic`, `GhostGlass`, `GhostPaper` (Assets + GameRender/Resources/Junk) | **Original (Cinder and Crown LLC).** Hand-authored neon tile plates with material glyphs (bolt / arrows / bottle / fold). Baked in-repo with PIL; no third-party stock; no generative service. Used as recycle suck VFX. |
| HUD / particles | DumpsterFrame, AlleyBackground, Spark*, Debris*, MagnetIcon, GemPack* | **Original (Cinder and Crown LLC).** Alley backdrop + dumpster frame + sparks/debris authored in-repo for this title (agent-assisted composite + hand cleanup). Ownership: Cinder and Crown LLC. Tooling: local image edit / bake scripts in-repo — not an external generative service of unknown terms. |
| SFX | `lock`, `crush`, `recycle`, `combo`, `levelup`, `magnet`, `ui` `.wav` | Original / procedural one-shots |
| BGM | `game_loop.wav`, `menu_loop.wav` | Original procedural beds, **64 s** loops (not 8 s stubs) |

## Fonts

| Font | License | Source |
|------|---------|--------|
| System / SF / Avenir Next (device) | Apple system fonts | Device only — not bundled |
| DejaVu (icon bake tooling only) | Bitstream Vera / DejaVu | Build machine; not shipped in app |

## Third-party code / SDKs

| Component | License | Notes |
|-----------|---------|-------|
| Google Mobile Ads / UMP | Google proprietary | Test app ids until prod IDs provided |
| StoreKit 2 | Apple | Product IDs stubbed — see `docs/STORE_STUBS.md` |

## Policy

- Do not ship generative art of unknown license.
- When adding CC-BY art, list author + URL here and in-app credits.
- Update this file in the same commit as any new raster/wav.
- Record tool + ownership terms for any generator-assisted raster in the Provenance column.
