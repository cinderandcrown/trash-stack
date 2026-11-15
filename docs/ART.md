# Trash Stack art notes

Steam-neon-punk style: magenta + teal neon, rainy alley, wet metal.

## Gameplay

- Junk item sprites in GameRender `Resources/Junk` + app asset catalog (baked rim light). Texture keys map from item ids (`bottle` → `tube.png`, `plank` → `scrap.png`, `bentPipe` → `bag.png`, `fridge` → `box.png`).
- FX: `SparkTeal`, `SparkMagenta`, `SparkGold`, `DebrisMetal`, `DebrisNeon` — baked alpha sparks/debris (no flat color squares).
- Environment / mascot: `AlleyBackground`, `DumpsterFrame`, `RaccoonIdle|Cheer|Panic`, `JunkyardScene`, `LaunchLogo`.
- Runtime FX uses textured sparks + short flashes/shake — jetsam-safe.

## Design

See `docs/DESIGN.md` for Recycling Night Shift rules.
