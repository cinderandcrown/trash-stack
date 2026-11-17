# Licenses — Trash Stack assets

Every in-game raster, font, and wav must be **CC0**, **CC-BY** (with attribution), or **original** (Cinder and Crown LLC). Replace anything of unknown provenance before store submission.

## Original (Cinder and Crown LLC, © 2026)

| Asset | Path(s) | Provenance |
|-------|---------|------------|
| App icon | `TrashStack/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | Original neon dumpster + raccoon mark; hand-composited / agent-baked RGB, no alpha |
| Launch logo | `LaunchLogo.imageset` (@3x 600×600) | Original neon card mark; shipped at 3x so launch UIImage is ~200 pt (not clipped) |
| Cinder & Crown mute logo | `CinderCrownMute.imageset` (@1x/@2x/@3x) | **Cinder & Crown logo, © Cinder and Crown LLC, used by permission.** Publisher ident only (phoenix + crown, no wordmark). Source PNG md5 `f4a3ffce2b58ddd4f12c010427782ac8` |
| Ident SFX | `ember_whoosh.wav` | Original procedural ember/whoosh; respects mute |
| Raccoon Idle / Cheer / Panic | `Resources/UI`, `Assets.xcassets`, `GameRender/.../HUD` | Original character art; rematted with opaque interior + soft exterior edge (not luminance-keyed) |
| Junk silhouettes | `can`, `bottle`, `plank`, `pipe`, `crate`, `tire`, `bentPipe`, `fridge` | Original material-language tiles (metal / plastic / glass / paper). Legacy alias files bag/box/scrap/tube deleted |
| HUD / particles | DumpsterFrame, AlleyBackground, Spark*, Debris*, MagnetIcon, GemPack* | Original alley / neon HUD rasters authored for this title |
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
