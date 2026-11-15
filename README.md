# Trash Stack

Neon junk / compactor puzzle by **Cinder and Crown LLC** (Trash Panda universe).

- Web: [`web/`](web/) → https://trash-stack.pages.dev/
- Native: Capacitor 8 → `ios/` + `android/`
- Store name: **Trash Stack: Neon Junk Puzzle** (home-screen: **Trash Stack**)
- Bundle ID: `com.cinderandcrown.trashstack` · ASC Apple ID `6834995780`
- Identity: **8×15** dumpster bin, junk triomino/pentomino set, compactor + recycle + Magnet

## Develop

```bash
npm ci
npm run build          # native.js + icon/splash assets
npx cap sync
npm run validate:web
```

Open native IDEs: `npm run cap:ios` / `npm run cap:android`.

## CI

| Workflow | Purpose |
|----------|---------|
| `web-validate.yml` | Offline + trademark smoke checks |
| `ios.yml` | Simulator build, screenshots + gameplay demo video (`app-store-review-evidence`); TestFlight upload **only** on `testflight/*` tags |
| `android.yml` | Debug APK always; signed AAB when keystore secrets exist |

Do **not** push `testflight/*` tags from agents — Fire Fox tags TestFlight builds.

## Docs

See [`docs/STORE.md`](docs/STORE.md) for listing copy, age rating, privacy, Play checklist, and trade-dress notes.
