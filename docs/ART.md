# Trash Stack art notes

Steam-neon-punk style: magenta + teal neon, rainy alley, wet metal.

- Junk piece sprites live in `TrashStack/Assets.xcassets/Junk.spriteatlas` (baked rim light).
- Environment / mascot: `AlleyBackground`, `DumpsterFrame`, `RaccoonIdle|Cheer|Panic`, `JunkyardScene`.
- Magpie `Assets` did not yet contain Trash Panda production art at time of import; new sprites were generated to match the intended steam-neon-punk Trash Panda look. Prefer swapping in official Magpie/Trash Panda atlas frames when those land.
- Glow is baked into textures. Runtime FX uses solid flashes/sparks/shake — no per-node glow or heavy shaders (jetsam-safe).
