# Licenses — Trash Stack assets

Every in-game raster, font, and wav must be **CC0**, **CC-BY** (with attribution), or **original** (Cinder and Crown LLC). Replace anything of unknown provenance before store submission.

## Original (Cinder and Crown LLC, © 2026)

| Asset | Path(s) | Notes |
|-------|---------|-------|
| App icon | `TrashStack/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | Neon dumpster + raccoon mark; opaque RGB |
| Launch logo | `TrashStack/Resources/UI/LaunchLogo.png` | |
| Raccoon Idle / Cheer / Panic | `Resources/UI`, `Assets.xcassets`, `GameRender/.../HUD` | True-alpha cutouts |
| Junk silhouettes | `can`, `bottle`, `plank`, `pipe`, `crate`, `tire`, `bentPipe`, `fridge` (+ legacy aliases tube/scrap/bag/box) | Material language: metal / plastic / glass / paper |
| HUD / particles | DumpsterFrame, AlleyBackground, Spark*, Debris*, MagnetIcon, GemPack* | |
| SFX / BGM | `TrashStack/Resources/Audio/*.wav` | Procedural / original; recycle/combo ≥0.4s, crush ≥0.5s |

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
