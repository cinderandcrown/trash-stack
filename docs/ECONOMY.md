# Trash Stack — Economy & F2P tuning

Clash-of-Clans-inspired **free + ads + IAP** model. Soft currency **Scrap** (⚙), premium **Neon Gems** (◆).  
Source of truth: `src/economy-config.js` + pure math in `src/economy-math.js` (unit-tested).

## Compliance (binding)

| Rule | Implementation |
|------|----------------|
| No real-money gambling / no cash-out | No wallets, no prize redemption |
| Odds for every random reward | Spin + all crates show `%` lines in UI |
| Never sell a random box for real money without odds | Crates are **earned**; IAP sells Gems / Remove Ads / Pass / packs only |
| No dark patterns aimed at kids | One-time offers capped; quiet hours; no launch nag; age ≤ **12+** |
| No purchase nagging (Nicholas) | Desire from gameplay + visible cosmetics — never pressure to buy |
| App Store 3.1.1 / 4.x + Play Real-Money Gambling & Families | IAP stubs use StoreKit/Play Billing when wired; ads family-safe config |

Age rating questionnaire target: **12+** max (not 17+).

## No-nag purchase rules (binding)

Players must **never feel nagged to buy**. Fun and completion are free; cosmetics create want.

| Rule | Cap / behavior |
|------|----------------|
| No purchase popups at **launch**, **mid-run**, or **right after a loss** | `denyContexts`: `launch`, `mid_run`, `after_loss` |
| Offers only in **Shop** or one small **dismissible badge** | `placements`: `shop`, `dismissible_badge` |
| Special-offer card | **≤1 per session**, only after **win** or **level-up** |
| Dismiss | One tap; **never re-shown that calendar day** (`maxSurfacesPerDay: 1`, `neverReshowSameDay`) |
| No fake countdown timers | `fakeCountdownTimers: false` |
| No confirmshaming copy | e.g. ban “No thanks, I like losing” — `confirmshaming: false` + banned patterns |
| Rewarded ads | Always **opt-in** |
| Interstitials | Existing caps only (≤1 / 3 overs; skip first 2 session runs) |
| Premium cosmetics | Natural showcase: other skins on records, pass previews, **try for one run** |
| Free path | Game fully fun and **completable for free** (`freeToPlayComplete`) |

Enforced in `ONE_TIME_OFFER` + `canSurfaceSpecialOffer` / `assertOfferFrequencyCaps` (unit-tested).

## Currencies

| | Scrap | Neon Gems |
|--|-------|-----------|
| Earn | Line crush, recycle, quests, login, chests, pass | Rare run drip (cap), chests, pass premium, IAP |
| Spend | Cosmetic shop, building upgrades | Speedups, streak freeze, gem shop cosmetics (optional), IAP stubs |
| Start | 80 (config) | 20 (config) |

Legacy **Shinies** migrate 1:1 into Scrap on load.

## IAP stubs (no product IDs yet)

| SKU key | Display | Contents |
|---------|---------|----------|
| `gems_40` … `gems_2500` | $0.99 – $49.99 | Gem packs |
| `starter_pack` | $2.99 one-time | 120 Gems + 500 Scrap + trail |
| `season_premium` | $4.99 / season | Premium pass lane |
| `remove_ads` | $4.99 | Remove Ads |

Special-offer framework: max **1 card / session**, max **1 / day**, only after win or level-up, shop or dismissible badge, 48h cooldown, quiet hours 21:00–08:00, optional copy — see **No-nag purchase rules**.

## Junkyard base (meta)

Buildings (Scrap + real-time timers; Gems speed up; builder slots):

| Building | Max Lv | Perk type |
|----------|--------|-----------|
| Recycler | 8 | Recycle Scrap bonus |
| Compactor | 8 | Crush Scrap bonus |
| Neon Sign | 6 | XP bonus + cosmetic glow (**not** leaderboard score) |
| Stash Vault | 5 | Chest slots + shorter chest timers |

Builders: **2** free, up to **4** (extra slot gem stub cost 350).  
Speedup: `ceil(remainingSec / 60)` Gems (min 1, max 200).

Perks are **run juice / economy**, never pay-to-win personal-best score.

## Season Pass

- **30 tiers**, 100 XP / tier, monthly season id in config  
- Free + premium tracks (cosmetics + Scrap; sparse Gems on premium only)  
- Premium lane stub until StoreKit/Play product exists  

## Chests

Earned from runs (weighted). Unlock timers; slots from Stash Vault.  
Open with wait, **Gem speedup**, or **rewarded ad** speedup. Odds always visible.

| Crate | Weight | Unlock | Notes |
|-------|--------|--------|-------|
| Dock Crate | 70 | 30m | Common |
| Neon Crate | 25 | 3h | Uncommon |
| Legend Crate | 5 | 8h | Rare |

See `CHESTS.*.odds` in config for exact `%` tables (must sum to 100 — enforced by tests).

## Dopamine loops

- Daily login calendar + escalating Scrap (`min(120, 5×day + 20×floor(day/7))`) + streak freeze (Gems)  
- Daily / weekly quests (existing hustles)  
- Lucky spin: 1 free/day + 1 rewarded ad; odds shown  
- Combo shake / particles / SFX; near-miss revive; level-up fanfare  
- Collection album: skins, trails, boards, raccoon outfits  

## Ads (unchanged caps)

- Rewarded: revive, double Scrap, spin, **chest speedup** — always **opt-in**  
- Interstitial: ≤1 / 3 game overs; never first 2 session runs  
- No banners in play  
- Remove Ads IAP stub  
- Never use ads or IAP prompts to pressure kids or block free play

## Notifications (local only)

Ask permission **after first win**, never at launch. Settings toggles per kind.  
Kinds: upgrade done, chest ready, daily reward, streak about to break, new season.  
Cap **~2/day** + quiet hours 21:00–08:00. No remote push server.

## Tuning without code changes

1. Edit `src/economy-config.js`  
2. `npm test` (economy math)  
3. `npm run build` (bundles into `web/economy.js` + native bridge)  

## Tests

```bash
npm test
```

Covers odds sums, upgrade queue, gem speedups, chest open, migration, season tiers, login streak, **offer frequency / no-nag caps**.
