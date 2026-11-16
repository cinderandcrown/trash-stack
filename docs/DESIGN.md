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
| Crate | 2×2 (single crate art, not 4 tiles) | paper |
| Tire | 2×2 (single round art) | plastic |
| Bent pipe | L of 3 | metal |
| Fridge | 2×3 (rare) | metal / plastic |

Max straight span is **3** (no 1×4 / I-tetromino shapes). Materials: **metal, plastic, glass, paper** only.

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

### Monetization guardrails (Nicholas)

**Mild pay-to-win is OK — just not crazy.** Paid items may **speed progress** and give a **modest edge** (e.g. Recycling Yard timer skips, run boosters, extra Snatch charges). Soft rules:

- Everything powerful must also be **earnable for free by playing** (no paid-only power).
- No gap so large that a **skilled free player can’t compete** (leaderboards, Shift stars, Daily Dumpster).
- Cosmetics stay swagger; progression buys are convenience / mild edge, not a wall.

**No-nagging still applies:** no purchase popups at launch, mid-run, or after a loss; at most **one dismissible offer per session**. See `docs/ECONOMY.md`.

## Controls (forgiving)

- **Drag anywhere** on the board to move · **tap** to rotate · **swipe down** to drop
- **PRESS** · **SNATCH** · hold/stash — large, thumb-safe, never under notch / home indicator
- Placement-insensitive: grab from any point on the playfield

## FTUE (~30–45 seconds)

Interactive first shift (not a text wall): almost-cluster gift → first recycle/chain → PRESS slam. Skip allowed. Then Endless + Daily. **Shift Mode hidden until handcrafted levels are real.**

## Docs

- Short GDD: this file. Mobile technical design: `docs/TECHNICAL.md`. Methods: `docs/VIBEGAMEDEV_METHODS.md`.

## Reference games (inspiration only — keep everything original)

Nicholas’s return-loop references: **Clash of Clans** and **Star Trek Fleet Commander**. Feel reference: **Call of Duty** (badass, punchy). Never copy systems, UI, or art — translate into Trash Stack’s junkyard night-shift identity.

### Backlog — after current pass is reviewed

Do **not** implement this section until the in-flight feel / FTUE / retention pass is reviewed. Then prioritize as backlog (no tags).

**Return loop (CoC / STFC → Recycling Yard)**

- **Recycling Yard** home base: upgrades paid with materials you recycled in runs (metal / plastic / glass / paper → yard buildings), not generic soft-currency spam.
- Upgrades that **finish while you’re away** (real-time timers) — the reason to open the app again.
- **Daily recycling-order goals** tied to the Yard (distinct from in-run order tickets).
- **Something to collect every visit** (finished upgrade, free crate, yard scrap pile) — no nagging; mild paid speedups OK if earnable free and not crazy (see Monetization).

**Feel (CoD → night-shift punch)**

- **Heavy, punchy PRESS**: hit-stop, screen shake, big crunch SFX (already aimed; deepen until it feels badass).
- A **satisfying rank-up** moment (Shift stars / Yard rank / Pass tier — one clear celebration beat).
- **Badass cosmetics** on the Season Pass (bin skins, chute flares, raccoon gear) — swagger, not power.

## Evidence (smoke)

Must show: material recycle, chain, press slam, order complete, Snatch, game over, **Daily Dumpster**, **share card**, **streak reward**. Video ≲150 MB with music + SFX. Judge screenshots side-by-side vs the previous build (agent eyes).
