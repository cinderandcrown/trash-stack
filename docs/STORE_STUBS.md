# Store / ads / privacy stubs (parallel track)

**Do not block the fun/P0 pass on these.** Nicholas will provide App Store Connect IDs when ready.

## Parallel checklist

| Item | Current | Needed for submission |
|------|---------|------------------------|
| AdMob app id | Google test `ca-app-pub-3940256099942544~1458002511` | Production app + unit IDs |
| ATT / UMP | Deferred until after first win | Keep deferred; fill privacy nutrition labels |
| `NSPrivacyTracking` / domains | Tracking flag may not match ATT use | Complete Privacy Manifest |
| StoreKit 2 products | `Configuration.storekit` + stub purchase set | Real product IDs; wire `Product.purchase` in Shop |
| Gem pack naming | “Neon Haul” (not “Crate”) | Register in ASC |
| Remove Ads / Pass SKUs | Stubbed | ASC + entitlements |
| SKAdNetwork IDs | Minimal list | Full AdMob SKAdNetwork list |
| Game Center leaderboards | `trashstack_endless` / `trashstack_daily` hooks | Register in ASC |
| Odds on random rewards | Shown on crate open | Keep for every random reward |

No purchase prompts at launch, mid-run, or after a loss (binding).
