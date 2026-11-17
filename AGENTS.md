# Agent notes — Trash Stack

Native Swift + SpriteKit + StoreKit 2. Magpie / App Store evidence via simulator smoke.

## Working methods

Follow **[docs/VIBEGAMEDEV_METHODS.md](docs/VIBEGAMEDEV_METHODS.md)** (incl. v2 Chong-U rules) for every gameplay pass:

- One system per pass; state current behavior → aim → files → how it shows in smoke video
- Core feel first, then progression, then come-back hooks
- Feel numbers in `feel.json`; one gym per system (`BoardGym`)
- Forgiving controls; safe-area HUD; chrome must not compete with the board
- Juice (hit-stop, shake, particles) required; no full-screen flash washes
- ~30s FTUE (move / rotate / clusters / press); juicy vertical slice only
- Deterministic smoke + side-by-side screenshot judgment after every pass
- Never name classic falling-block trademarks (or tetromino / line-clear / letter piece names)

Also see `docs/DESIGN.md`, `docs/TECHNICAL.md`, `docs/ECONOMY.md`, `docs/ART.md`, `docs/STORE.md`.

## CI / shipping

- Push feature work on `cursor/*-497e` branches; open/update PRs via agent tools
- Agents push **no tags** (TestFlight tags are owned by humans)
- Smoke must show recycle / chain / press / orders / Snatch / GO, plus Daily Dumpster, share card, and streak when retention is in scope
