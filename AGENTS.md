# Agent notes — Trash Stack

Native Swift + SpriteKit + StoreKit 2. Magpie / App Store evidence via simulator smoke.

## Working methods

Follow **[docs/VIBEGAMEDEV_METHODS.md](docs/VIBEGAMEDEV_METHODS.md)** for every gameplay pass:

- One system per pass; state current behavior → aim → files → how it shows in smoke video
- Core feel first, then progression, then come-back hooks
- Feel numbers in JSON/plist; board gym for isolated setups
- Juice (hit-stop, shake, particles) required; no full-screen flash washes
- Deterministic smoke video + screenshots after every pass
- Never use the word “Tetris” (or tetromino / line-clear / letter piece names)

Also see `docs/DESIGN.md`, `docs/ECONOMY.md`, `docs/ART.md`, `docs/STORE.md`.

## CI / shipping

- Push feature work on `cursor/*-497e` branches; open/update PRs via agent tools
- Agents push **no tags** (TestFlight tags are owned by humans)
- Smoke must show recycle / chain / press / orders / Snatch / GO, plus Daily Dumpster, share card, and streak when retention is in scope
