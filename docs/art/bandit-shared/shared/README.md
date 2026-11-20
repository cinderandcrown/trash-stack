# The Bandit — shared character library

One cyberpunk raccoon bandit for **The Neon City Bandit** and **Trash Stack**. Both games should use these same poses, expressions, and this neon painted style. Game-specific animation packs come after Nicholas approves this sheet.

Do not mix in the earlier cute cartoon Trash Stack raccoon. This is the goggles-and-cables bandit from Neon City Bandit, remade at Higgsfield quality.

## Who uses what

| Asset | File | The Neon City Bandit | Trash Stack | Both |
| --- | --- | --- | --- | --- |
| Hero front | `hero-front.png` | Promo, menus | Front hero, idle slot | App icons and promo |
| Side view (faces right) | `side-right.png` | Side-scroller keyframe, walk/run/jump base | — | — |
| Mid-jump pounce | `pounce.png` | Attack / pounce keyframe | — | — |
| Victory | `victory.png` | Level-clear / disco-dance key | — | — |
| Idle / neutral head | `head-idle.png` | — | Idle expression | — |
| Cheer / grin head | `head-cheer.png` | — | Cheer expression | — |
| Determined head | `head-determined.png` | Heist focus, pounce face | Optional focused look | Shared expression |
| Panic head | `head-panic.png` | — | Panic expression | — |
| Game over head | `head-gameover.png` | — | Game-over expression | — |
| Hurt head | `head-hurt.png` | Damage reaction | — | — |
| Character sheet | `character-sheet.png` | Review and art direction | Review and art direction | Source of truth |

A copy of the sheet also lives at `../character-sheet.png`. License terms are in `../LICENSE.md`.

## What's in this folder

Transparent 1024×1024 PNGs, plus the assembled sheet. Raw Higgsfield outputs (before local alpha cleanup) are in `../raw/`. A proven idle animation pipeline test (10-frame 256×256 loop, GIF, and contact sheet) is in `../anim-test/`.

## What's next

After this sheet is approved, redo the animated sprites on Higgsfield from these keyframes (see `../SPRITE-SPEC.md`). Side view and front hero are the clean bases for that work.
