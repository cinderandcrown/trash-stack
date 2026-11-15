/**
 * Trash Stack economy — data-driven tuning (Clash-style F2P).
 * Edit numbers here / in docs/ECONOMY.md; keep math in economy-math.js.
 * No real-money gambling: random rewards show odds; crates never sold for cash without odds.
 */

export const ECONOMY_VERSION = 3;

/** Soft currency earned in play (migrated from legacy "shinies"). */
export const SOFT = {
  id: 'scrap',
  label: 'Scrap',
  symbol: '⚙',
  startAmount: 80,
};

/** Premium currency — rare in play, buyable via stubbed IAP. */
export const PREMIUM = {
  id: 'gems',
  label: 'Neon Gems',
  symbol: '◆',
  startAmount: 20,
  rareEarnPerRunCap: 2,
};

/** Gem packs — StoreKit/Play Billing product IDs left empty (stubs). Prices in USD display. */
export const GEM_PACKS = [
  { id: 'gems_40', gems: 40, priceUsd: 0.99, productId: '', badge: null },
  { id: 'gems_210', gems: 210, priceUsd: 4.99, productId: '', badge: 'Popular' },
  { id: 'gems_450', gems: 450, priceUsd: 9.99, productId: '', badge: null },
  { id: 'gems_1200', gems: 1200, priceUsd: 19.99, productId: '', badge: 'Best value' },
  { id: 'gems_2500', gems: 2500, priceUsd: 49.99, productId: '', badge: null },
];

export const STARTER_PACK = {
  id: 'starter_pack',
  label: 'Dock Starter Pack',
  gems: 120,
  scrap: 500,
  trail: 'cyan',
  priceUsd: 2.99,
  productId: '',
  oneTime: true,
};

/**
 * Special-offer framework — desire from gameplay/cosmetics, never purchase nagging.
 * Nicholas rule: players must never feel pressured to buy.
 */
export const ONE_TIME_OFFER = {
  enabled: true,
  /** At most one special-offer card per play session. */
  maxPerSession: 1,
  /** Once dismissed, never re-show that calendar day. */
  maxSurfacesPerDay: 1,
  neverReshowSameDay: true,
  cooldownHours: 48,
  quietHours: { start: 21, end: 8 },
  /** Only after a win or level-up — never launch / mid-run / after loss. */
  allowContexts: ['after_win', 'after_level_up'],
  denyContexts: ['launch', 'mid_run', 'after_loss'],
  /** Offers live in Shop or as one small dismissible badge — not blocking popups. */
  placements: ['shop', 'dismissible_badge'],
  dismissOneTap: true,
  fakeCountdownTimers: false,
  confirmshaming: false,
  bannedCopyPatterns: ['no thanks, i like losing', "don't miss out", 'last chance'],
  copy: 'Optional offer — never required to play.',
  rewardedAdsOptInOnly: true,
  freeToPlayComplete: true,
  premiumShowcase: {
    leaderboardOtherSkins: true,
    passPreviews: true,
    tryForOneRun: true,
  },
};

export const BUILDINGS = {
  recycler: {
    id: 'recycler',
    name: 'Recycler',
    blurb: 'Bonus Scrap from recycle pops.',
    maxLevel: 8,
    // costScrap[level-1 → level], durationSec, perk
    levels: [
      { cost: 0, sec: 0, perk: { scrapRecycleBonus: 0 } },
      { cost: 120, sec: 60, perk: { scrapRecycleBonus: 0.05 } },
      { cost: 280, sec: 180, perk: { scrapRecycleBonus: 0.1 } },
      { cost: 520, sec: 600, perk: { scrapRecycleBonus: 0.15 } },
      { cost: 900, sec: 1800, perk: { scrapRecycleBonus: 0.2 } },
      { cost: 1500, sec: 3600, perk: { scrapRecycleBonus: 0.25 } },
      { cost: 2400, sec: 7200, perk: { scrapRecycleBonus: 0.3 } },
      { cost: 4000, sec: 14400, perk: { scrapRecycleBonus: 0.4 } },
    ],
  },
  compactor: {
    id: 'compactor',
    name: 'Compactor',
    blurb: 'Bonus Scrap from row crushes (cosmetic juice too).',
    maxLevel: 8,
    levels: [
      { cost: 0, sec: 0, perk: { scrapClearBonus: 0 } },
      { cost: 150, sec: 90, perk: { scrapClearBonus: 0.05 } },
      { cost: 320, sec: 240, perk: { scrapClearBonus: 0.1 } },
      { cost: 600, sec: 900, perk: { scrapClearBonus: 0.15 } },
      { cost: 1000, sec: 2400, perk: { scrapClearBonus: 0.2 } },
      { cost: 1700, sec: 4800, perk: { scrapClearBonus: 0.25 } },
      { cost: 2800, sec: 9600, perk: { scrapClearBonus: 0.3 } },
      { cost: 4500, sec: 18000, perk: { scrapClearBonus: 0.4 } },
    ],
  },
  neonSign: {
    id: 'neonSign',
    name: 'Neon Sign',
    blurb: 'Cosmetic board glow + tiny XP bonus (not score P2W).',
    maxLevel: 6,
    levels: [
      { cost: 0, sec: 0, perk: { xpBonus: 0, glow: 0 } },
      { cost: 200, sec: 120, perk: { xpBonus: 0.05, glow: 1 } },
      { cost: 450, sec: 600, perk: { xpBonus: 0.08, glow: 2 } },
      { cost: 800, sec: 1800, perk: { xpBonus: 0.1, glow: 3 } },
      { cost: 1400, sec: 5400, perk: { xpBonus: 0.12, glow: 4 } },
      { cost: 2200, sec: 10800, perk: { xpBonus: 0.15, glow: 5 } },
    ],
  },
  stashVault: {
    id: 'stashVault',
    name: 'Stash Vault',
    blurb: 'Extra chest slot + shorter chest timers.',
    maxLevel: 5,
    levels: [
      { cost: 0, sec: 0, perk: { chestSlots: 2, chestTimeMult: 1 } },
      { cost: 250, sec: 300, perk: { chestSlots: 3, chestTimeMult: 0.95 } },
      { cost: 700, sec: 1800, perk: { chestSlots: 3, chestTimeMult: 0.9 } },
      { cost: 1600, sec: 7200, perk: { chestSlots: 4, chestTimeMult: 0.85 } },
      { cost: 3200, sec: 14400, perk: { chestSlots: 4, chestTimeMult: 0.75 } },
    ],
  },
};

/** Builder slots: free slots + optional gem unlock stub. */
export const BUILDERS = {
  freeSlots: 2,
  gemUnlockSlotCost: 350,
  maxSlots: 4,
};

/** Gem cost to skip remaining upgrade/chest time: ceil(remainingSec / secPerGem). */
export const SPEEDUP = {
  secPerGem: 60,
  minGems: 1,
  maxGemsPerAction: 200,
};

export const SEASON_PASS = {
  seasonId: 1,
  label: 'Neon Season',
  tiers: 30,
  xpPerTier: 100,
  premiumProductId: '', // stub
  premiumPriceUsd: 4.99,
  // Free/premium rewards by tier (1..30). Cosmetics & soft currency only on free; gems sparse on premium.
  free: [
    { at: 1, scrap: 40 },
    { at: 2, scrap: 50 },
    { at: 3, trail: 'cyan' },
    { at: 4, scrap: 60 },
    { at: 5, scrap: 80 },
    { at: 6, bg: 'rooftop' },
    { at: 7, scrap: 90 },
    { at: 8, scrap: 100 },
    { at: 9, skin: 'glass' },
    { at: 10, scrap: 140 },
    { at: 11, scrap: 80 },
    { at: 12, scrap: 90 },
    { at: 13, trail: 'mag' },
    { at: 14, scrap: 100 },
    { at: 15, scrap: 120 },
    { at: 16, bg: 'alley' },
    { at: 17, scrap: 120 },
    { at: 18, scrap: 140 },
    { at: 19, skin: 'gold' },
    { at: 20, scrap: 180 },
    { at: 21, scrap: 100 },
    { at: 22, scrap: 110 },
    { at: 23, trail: 'gold' },
    { at: 24, scrap: 130 },
    { at: 25, scrap: 150 },
    { at: 26, bg: 'subway' },
    { at: 27, scrap: 160 },
    { at: 28, scrap: 180 },
    { at: 29, skin: 'circuit' },
    { at: 30, scrap: 250 },
  ],
  premium: [
    { at: 1, scrap: 80, gems: 5 },
    { at: 2, scrap: 100 },
    { at: 3, trail: 'lime' },
    { at: 4, scrap: 120 },
    { at: 5, gems: 10 },
    { at: 6, scrap: 140 },
    { at: 7, scrap: 150 },
    { at: 8, gems: 10 },
    { at: 9, skin: 'mask' },
    { at: 10, scrap: 220, gems: 15 },
    { at: 11, scrap: 120 },
    { at: 12, gems: 10 },
    { at: 13, scrap: 140 },
    { at: 14, scrap: 150 },
    { at: 15, gems: 20 },
    { at: 16, scrap: 180 },
    { at: 17, scrap: 180 },
    { at: 18, gems: 15 },
    { at: 19, skin: 'sticker' },
    { at: 20, scrap: 300, gems: 25 },
    { at: 21, scrap: 160 },
    { at: 22, gems: 15 },
    { at: 23, scrap: 180 },
    { at: 24, scrap: 200 },
    { at: 25, gems: 30 },
    { at: 26, scrap: 220 },
    { at: 27, scrap: 240 },
    { at: 28, gems: 20 },
    { at: 29, skin: 'haze' },
    { at: 30, scrap: 400, gems: 50 },
  ],
};

/**
 * Chest tables — odds MUST sum to 100 (percent). Never sell these for real money without odds UI.
 */
export const CHESTS = {
  dock_crate: {
    id: 'dock_crate',
    name: 'Dock Crate',
    unlockSec: 30 * 60,
    earnWeight: 70,
    slots: true,
    odds: [
      { label: '40 Scrap', kind: 'scrap', n: 40, pct: 35 },
      { label: '80 Scrap', kind: 'scrap', n: 80, pct: 25 },
      { label: '120 Scrap', kind: 'scrap', n: 120, pct: 15 },
      { label: '2 Gems', kind: 'gems', n: 2, pct: 10 },
      { label: '5 Gems', kind: 'gems', n: 5, pct: 5 },
      { label: 'Cosmetic LOOK', kind: 'cosmetic', n: 0, pct: 10 },
    ],
  },
  neon_crate: {
    id: 'neon_crate',
    name: 'Neon Crate',
    unlockSec: 3 * 60 * 60,
    earnWeight: 25,
    slots: true,
    odds: [
      { label: '100 Scrap', kind: 'scrap', n: 100, pct: 30 },
      { label: '200 Scrap', kind: 'scrap', n: 200, pct: 25 },
      { label: '5 Gems', kind: 'gems', n: 5, pct: 20 },
      { label: '12 Gems', kind: 'gems', n: 12, pct: 10 },
      { label: 'Cosmetic LOOK', kind: 'cosmetic', n: 0, pct: 15 },
    ],
  },
  legend_crate: {
    id: 'legend_crate',
    name: 'Legend Crate',
    unlockSec: 8 * 60 * 60,
    earnWeight: 5,
    slots: true,
    odds: [
      { label: '250 Scrap', kind: 'scrap', n: 250, pct: 25 },
      { label: '400 Scrap', kind: 'scrap', n: 400, pct: 20 },
      { label: '15 Gems', kind: 'gems', n: 15, pct: 25 },
      { label: '30 Gems', kind: 'gems', n: 30, pct: 15 },
      { label: 'Rare LOOK', kind: 'cosmetic', n: 0, pct: 15 },
    ],
  },
};

export const LOGIN_STREAK = {
  capScrap: 120,
  formulaNote: 'min(cap, 5*day + 20*floor(day/7))',
  freezeCostGems: 15,
  freezeMaxOwned: 2,
};

export const SPIN = {
  freePerDay: 1,
  rewardedExtraPerDay: 1,
  oddsEqualSlices: true,
};

export const NOTIFICATIONS = {
  askAfterFirstWin: true,
  neverAtLaunch: true,
  maxPerDay: 2,
  quietHours: { start: 21, end: 8 },
  kinds: ['upgrade_done', 'chest_ready', 'daily_reward', 'streak_risk', 'new_season'],
};

export const ADS = {
  interstitialEveryNOvers: 3,
  interstitialSkipFirstRuns: 2,
  bannersInPlay: false,
  rewarded: ['revive', 'double', 'spin', 'chest_speed'],
};

export const REMOVE_ADS = {
  productId: '',
  priceUsd: 4.99,
  stub: true,
};

export const COMPLIANCE = {
  maxAgeRating: '12+',
  noRealMoneyGambling: true,
  noCashOut: true,
  showOddsForRandom: true,
  noPaidLootWithoutOdds: true,
  noDarkPatternsAimedAtKids: true,
  noPurchaseNagging: true,
  noPurchasePopupsAtLaunch: true,
  noPurchasePopupsMidRun: true,
  noPurchasePopupsAfterLoss: true,
  rewardedAdsOptInOnly: true,
  freeToPlayComplete: true,
};

/** Browser global for the offline shell (non-module script). */
export function attachEconomyGlobal(target = globalThis) {
  target.TrashEconomyConfig = {
    ECONOMY_VERSION,
    SOFT,
    PREMIUM,
    GEM_PACKS,
    STARTER_PACK,
    ONE_TIME_OFFER,
    BUILDINGS,
    BUILDERS,
    SPEEDUP,
    SEASON_PASS,
    CHESTS,
    LOGIN_STREAK,
    SPIN,
    NOTIFICATIONS,
    ADS,
    REMOVE_ADS,
    COMPLIANCE,
  };
}

attachEconomyGlobal();
