# Trash Stack — technical design (mobile)

Mobile-aware companion to `docs/DESIGN.md`. Update this file every gameplay pass.

## Stack

- Native **Swift** + **SpriteKit** playfield + **SwiftUI** meta
- Packages: `GameCore` (pure rules), `GameRender` (CompactorScene), `Services` (profile, audio, ads, StoreKit, GameKit)
- StoreKit 2; Magpie simulator smoke for App Store evidence

## Layout & safe areas

- Play HUD and action row respect **safeAreaInsets** (notch / Dynamic Island / home indicator).
- Sprite playfield may bleed horizontally; chrome (score, tickets, PRESS/SNATCH) stays inside safe bounds.
- Controls are placement-insensitive: drag **anywhere on the board** to move, tap to rotate, swipe down to hard-drop. PRESS / SNATCH / HOLD are large, thumb-reachable.

## Systems & gyms

One isolated gym shot / API per system (seeded, deterministic):

| System | Gym entry | Purpose |
|--------|-----------|---------|
| Board + spawner | `BoardGym.board` / shot `game` | Mid-fill bin + active junk |
| Clusters | `BoardGym.clusters` / shot `recycle` | Metal cluster ready to suck |
| Press | `BoardGym.press` / shot `compactor` | Full meter + bottom rows |
| Snatch | `BoardGym.snatch` | Snatch-ready mid board |
| Tickets | `BoardGym.tickets` | Orders in progress |

Feel tunables live in `Packages/GameCore/Sources/GameCore/Resources/feel.json` (fall / lock / press / pop / hit-stop / shake). No new magic numbers in scene code.

## Audio / art

- SFX: recycle, combo, crush, lock, magnet, ui, levelup — audition every change; reject harsh mismatches.
- BGM: `game_loop`, `menu_loop` (debug switch planned; review builds mute debug).
- Licenses: see `docs/ART.md` / LICENSES when assets are added.

## FTUE (~30s)

1. Move — drag junk sideways  
2. Rotate — tap  
3. Clusters — 4+ same material → chute  
4. Press — fill meter, slam  

Then drop into Shift / Endless / Daily. No feature sprawl beyond the juicy vertical slice.

## Smoke judgment (agent eyes)

After each pass: compare new smoke screenshots side-by-side with the previous artifact set. Keep only changes that are **clearly better** on feel or clarity. Green CI ≠ fun.
