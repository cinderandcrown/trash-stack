# Asset manifest (committed)

Track atlases, frame sizes, SFX, and BGM. Update when art/audio changes.

## Junk / board (GameRender + Assets)

| Key | Role | Notes |
|-----|------|-------|
| can, tube, scrap, pipe, crate, tire, bag, box | Junk textures | Max straight span 3; crate/tire rendered as single 2×2 |
| DumpsterFrame, AlleyBackground | Playfield | Board owns color vs quiet HUD chrome |
| SparkTeal, SparkMagenta, SparkGold, DebrisMetal, DebrisNeon | Particles | Local flashes only |
| RaccoonIdle, RaccoonCheer, RaccoonPanic, RaccoonGameOver | Helper (Bandit placeholder) | Mood slot — on-model cyberpunk poses incoming |
| BinInterior, Slam01/02, ClearBurst, CellPlate, tiles | Playfield / VFX | Higgsfield art pack (see docs/art/TS_ART_LICENSE.md) |

## Audio (`TrashStack/Resources/Audio`)

| File | Role | Audition note |
|------|------|----------------|
| game_loop.wav | In-run BGM | |
| menu_loop.wav | Meta BGM | |
| recycle.wav | Cluster pop | Pitch escalates on chains |
| combo.wav | Chain accent | |
| crush.wav | PRESS slam | Must feel meaty, not harsh |
| lock.wav | Soft lock | |
| magnet.wav | Snatch | |
| ui.wav | UI taps | |
| levelup.wav | Orders / level | |

Licenses: see `docs/ART.md`. Commercial-safe / CC0 preferred.
