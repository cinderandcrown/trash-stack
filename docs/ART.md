# Trash Stack art notes

Steam-neon-punk style: magenta + teal neon, rainy alley, wet metal.

## Gameplay

- Junk item sprites in GameRender `Resources/Junk` + app asset catalog (baked rim light). Texture names match JunkID (`bottle`, `plank`, `bentPipe`, `fridge`, …). Legacy alias files removed.
- FX: `SparkTeal`, `SparkMagenta`, `SparkGold`, `DebrisMetal`, `DebrisNeon` — baked alpha sparks/debris (no flat color squares).
- Board / VFX (Higgsfield pack): `BinInterior`, material tiles (`can`/`glass`/`plastic`/`cardboard`/`pizza`/`banana`/`tire`), `Slam01`/`Slam02`, `ClearBurst`, `CellPlate`.
- Environment / mascot: `AlleyBackground`, `DumpsterFrame`, Bandit mood heads (`RaccoonIdle|Cheer|Panic|GameOver`), title `BanditHero`, `JunkyardScene`, `LaunchLogo`.
- Runtime FX uses textured sparks + short flashes/shake — jetsam-safe.

## Design

See `docs/DESIGN.md` for Recycling Night Shift rules.
