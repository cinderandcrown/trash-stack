# BanditLoops

Front-facing sprite loops (`idle_front`, `cheer`, `panic`, `disco_dance`, `gameover`) derived from the approved Higgsfield bandit keyframes in `docs/art/bandit-shared` (hero-front, victory, pounce, heads).

- Studio: Cinder and Crown LLC
- Generator: Higgsfield
- Format: 256×256 transparent PNG, bottom-center anchor, 10 frames @ ~12.5 fps
- Filenames: `<loop>_00.png` … `<loop>_09.png` (unique; XcodeGen flattens resource folders)
- Fallback: static mood heads (`RaccoonIdle` / `RaccoonCheer` / `RaccoonPanic`) remain in Resources/UI

When `bandit-sprites.tar.gz` (official motion loops) is attached, replace these frames in place.
