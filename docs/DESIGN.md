# Trash Stack — Recycling Night Shift

Binding design for Magpie / Nicholas. Trade-dress distance from Tetris is mandatory.
The game must feel **genuinely fun** and give people a reason to **come back daily**.

## Elevator pitch

You work the **night shift** in a neon junkyard. Drop junk **items** into an 8×14 **compactor bin**, **recycle** material clusters, and **slam the press** when the meter is ready. Order tickets give each run a goal. Modes, Daily Dumpster, streaks, and the Junkyard base keep the night shift sticky — without nagging.

## Board

- **8 columns × 14 visible rows**, styled as a junkyard compactor bin.
- Not 10×20. Not a classic well.
- Lose when junk **overflows the top lip** of the bin.

## Junk items (not block-shape piece letters)

| Item | Footprint | Typical material |
|------|-----------|------------------|
| Can | 1×1 | metal |
| Bottle | 1×2 | glass / plastic |
| Plank | 1×3 | paper |
| Pipe | 1×3 | metal |
| Crate | 2×2 | paper |
| Tire | 2×2 (round art) | plastic |
| Bent pipe | L of 3 | metal |
| Fridge | 2×3 (rare) | metal / plastic |

Materials: **metal, plastic, glass, paper** only.

**Forbidden:** UI text, code identifiers, or asset names that say Tetris, tetromino, “line clear”, or letter piece names **T / S / Z / I / O**.

## Core loop

1. **Drop** junk items (drag move, tap rotate when non-square, swipe down to drop).
2. **Recycle:** **4+** orthogonally connected same-material cells → sucked into the matching chute. Sticky excluded until pressed.
3. **Settle** → possible **Recycle Chain** combos.
4. **PRESS meter** fills on place. When full, tap **PRESS** to crush the **bottom 2 rows** into scrap (player-timed).
5. **Order tickets** (1–3 / run) → XP, gems, Pass XP.
6. **Snatch** once per run (raccoon helper).
7. **Hazards** (later Shift levels): leaking battery, sticky goo; plus magnets / conveyor belts as districts unlock.

No full-row automatic “line clear.”

## Core fun (feel)

Every recycle must feel great:

- Escalating **chain SFX pitch**
- **Chute suction** VFX on recycle
- **Screen pulse** on big chains (3+)
- **Meaty PRESS slam**: shake + scrap shower particles
- **Near-miss tension** music bed when junk nears the top lip
- Clear **next-item preview (2)** + **hold / stash slot** so players can plan chains
- Queued popups: RECYCLE / CHAIN / PRESS SLAM / ORDER DONE (no overlap)

## Modes

### Shift Mode (levels)

Handcrafted levels with order tickets and **3-star goals**, set across junkyard **districts**. Mechanics roll out slowly (batteries → sticky → magnets → conveyor belts). Stars gate cosmetics and Pass XP.

### Endless Night Shift

Survival / high-score mode. Submits to **Game Center** leaderboard `trashstack_endless`.

### Daily Dumpster

One **seeded** puzzle per calendar day (UTC date seed), **same for everyone**. Leaderboard `trashstack_daily`. End screen shows a **shareable emoji result card** (Wordle-style grid + score line).

## Come-back hooks (no nagging)

- **Daily streak** with escalating Scrap/Gem rewards; **one free streak saver per week**
- **Daily + weekly quests**
- **Junkyard base** upgrades with **real-time timers** (primary come-back reason)
- **Free crate every 4 hours** (cap 2 waiting)
- **Opt-in local push**, max **1/day**, only after first win (never at launch)
- **Season Pass**: free + premium **cosmetic** tracks (bin skins, item skins, chute effects, raccoon outfits)
- **Game Center achievements** (first recycle, 5× chain, press slam, daily clear, streak 7, etc.)

### Monetization guardrails

No purchase popups at launch, mid-run, or after a loss. At most **one dismissible offer per session**. Soft currency from play; cosmetics/convenience only. See `docs/ECONOMY.md`.

## Controls

- Drag · tap rotate · flick drop · **PRESS** · **SNATCH** · stash/hold slot

## Tutorial

Three interactive beats: place → material recycle of 4+ → fill and slam PRESS.

## Evidence (smoke)

Must show: material recycle, chain, press slam, order complete, Snatch, game over, **Daily Dumpster**, **share card**, **streak reward**. Video ≲150 MB with music + SFX.
