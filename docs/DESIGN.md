# Trash Stack — Recycling Night Shift

Binding design for Magpie / Nicholas. Trade-dress distance from Tetris is mandatory.

## Elevator pitch

You work the **night shift** in a neon junkyard. Drop junk **items** into an 8×14 **compactor bin**, **recycle** material clusters, and **slam the press** when the meter is ready. Order tickets give each run a goal. Meta (Junkyard, Season Pass, shop, quests, spin) stays.

## Board

- **8 columns × 14 visible rows**, styled as a junkyard compactor bin.
- Not 10×20. Not a classic well.
- Lose when junk **overflows the top lip** of the bin.

## Junk items (not block-shape piece letters)

Each falling unit is a **junk item** with a footprint and a **material** (color + icon):

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

**Forbidden:** any UI text, code identifier, or asset name that says Tetris, tetromino, “line clear”, or uses letter piece names **T / S / Z / I / O**. Items are named by what they are (can, bottle, plank, …).

Crate/tire are **junk objects** (crate / tire art), not letter-named block shapes.

## Core loop

1. **Drop** junk items into the bin (drag move, tap rotate when the footprint isn’t square, swipe down to drop).
2. **Recycle:** when **4+ orthogonally connected cells of the same material** touch, that cluster is **recycled** — sucked into the matching recycle chute with VFX. Sticky cells are excluded until pressed.
3. **Settle:** items above fall under gravity; new clusters can fire → **Recycle Chain** combos.
4. **Press meter:** fills as you place items. When full, tap **PRESS** to slam the hydraulic press: the **bottom 2 rows** of mixed junk crush into **scrap** (score + scrap currency). Player-timed, not automatic row clears.
5. **Order tickets:** 1–3 per run (e.g. “Recycle 20 glass”, “Make a 3× chain”). Completing them grants XP, gems, and Pass XP.
6. **Snatch** (once per run): raccoon helper removes any one locked item from the board.
7. **Hazards** (later levels): leaking battery converts neighbors toward metal; sticky goo can’t recycle until pressed.

There is **no full-row “line clear”** win condition. Compactor slam is the only bottom-row crush, and it is a deliberate button press.

## Controls

- Drag horizontally to move the active item
- Tap to rotate (skipped for square footprints)
- Swipe / flick down to drop
- Tap **PRESS** when the meter is full
- Tap **SNATCH** once per run (when charged)

## Presentation

- Neon rainy alley behind the bin; dumpster frame; Trash Panda / Bandit’s cousin raccoon
- Smooth tweened falls; recycle suck FX; press squash + shake; styled COMBO / RECYCLE CHAIN / PRESS SLAM popups (queued, not overlapping)
- Branded dark launch screen (no white flash)

## Meta (unchanged intent)

Junkyard base, Season Pass, Gem Shop, quests, daily spin with odds shown, no-nag monetization — see `docs/ECONOMY.md`.

## Tutorial

First three interactive moves teach: (1) place an item, (2) form a material recycle of 4+, (3) fill and slam the press. Help copy repeats material matching + press.

## Evidence (smoke)

Must show: material cluster recycle, Recycle Chain, press slam, order ticket complete, Snatch, game over. Gameplay video ≲150 MB with music + SFX.
