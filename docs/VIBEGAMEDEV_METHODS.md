# Vibe Game Dev methods — agent brief (Swift / SpriteKit)

Native Swift + SpriteKit + StoreKit 2 only. Imitate this repo's architecture.

## How to take work

- Write down the one-minute loop (drop junk, form material clusters, time the press, fill the order ticket). One system per pass; state the current behavior, the aim, the files touched, and how it will be VISIBLE in the smoke video. Each pass small enough to throw away. Core feel first, then progression, then come-back hooks.
- Keep a committed asset manifest (atlases, frame sizes, SFX, BGM).

## Gym and tunability

- A board gym: spawn any junk piece or cluster state on demand and trigger the press, Snatch or tickets in isolation.
- Feel numbers in JSON/plist (fall speed and interpolation, lock delay, press timing, cluster-pop timing, hit-stop, shake). No magic numbers.
- Debug overlay for timings and audio mute; review builds ship with debug off.

## Juice

- Cluster pops and press crushes get hit-stop (short normally, longer on big combos), noise-based screen shake, particles and squash/stretch on the beat.
- Flashes are brief, local and on a cooldown; never a full-screen wash.
- Graphics without juice are not done.

## Audio

- Not complete without SFX and music. Several BGM candidates switchable in the debug panel. Report cost before any paid audio.

## Art

- Free, commercial-safe assets only (CC0 first, CC-BY with attribution), logged in a LICENSES file. Normalize scale and alpha, and review a contact sheet before import.

## QA

- After every pass, a continuous deterministic smoke video (seeded RNG, an explicit ready signal, an outcome assertion, fail on unexpected logs) plus screenshots. Green CI is not the same as fun.
- Describe bugs by what's visible, then fix. No leftover debug strings. Never use classic falling-block trademarks anywhere.

## V2 (Chong-U) — mobile feel and judgment

- Keep a **short GDD** and a **mobile-aware technical design** in `docs/` and update them per pass (`docs/DESIGN.md`, `docs/TECHNICAL.md`).
- Controls are **placement-insensitive and forgiving** (drag anywhere to move a piece, tap to rotate, swipe down to drop), with nothing hidden under the notch or home indicator.
- **One gym per system** (board and junk spawner, clusters, press, Snatch, tickets).
- Background and HUD colors must **not compete with the board**.
- **Agent eyes:** change things, judge the smoke screenshots side by side against the previous build, and iterate until clearly better.
- Listen to every SFX; reject harsh or mismatched ones.
- Before release, a **~30-second FTUE** that teaches move, rotate, clusters and the press. Ship a **juicy vertical slice**; no feature sprawl.
