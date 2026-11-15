/**
 * Season 1 — Neon Dumpster (Fortnite-style pass, data-driven).
 * New seasons = new files under src/seasons/; register in index.js.
 */

const TIERS = 100;
const XP_PER_TIER = 100;

/** Premium pass ~$9.99 → 450 Gems (matches gems_450 pack display). */
const PREMIUM_GEM_COST = 450;

const FREE_LANDMARKS = {
  1: { scrap: 50, preview: { kind: 'scrap', label: '50 Scrap' } },
  5: { trail: 'cyan', preview: { kind: 'trail', label: 'Cyan Sparks', swatch: '#00f5ff' } },
  10: { bg: 'rooftop', preview: { kind: 'board', label: 'Rooftop Board', swatch: '#1a2040' } },
  15: { banner: 'dock_flag', preview: { kind: 'banner', label: 'Dock Flag' } },
  20: { skin: 'glass', preview: { kind: 'skin', label: 'Glass Blocks', swatch: '#9ef6ff' } },
  25: { emote: 'wave', preview: { kind: 'emote', label: 'Wave Emote' } },
  30: { crushFx: 'spark_pop', preview: { kind: 'crush', label: 'Spark Crush' } },
  35: { scrap: 200, preview: { kind: 'scrap', label: '200 Scrap' } },
  40: { trail: 'mag', preview: { kind: 'trail', label: 'Magenta Dust', swatch: '#ff2bd6' } },
  45: { outfit: 'hoodie', preview: { kind: 'outfit', label: 'Neon Hoodie' } },
  50: { bg: 'alley', preview: { kind: 'board', label: 'Alley Board', swatch: '#241018' } },
  55: { banner: 'neon_strip', preview: { kind: 'banner', label: 'Neon Strip Banner' } },
  60: { skinSet: 'pipe_kit', preview: { kind: 'skinSet', label: 'Pipe Kit Blocks' } },
  65: { emote: 'flex', preview: { kind: 'emote', label: 'Flex Emote' } },
  70: { crushFx: 'hydraulic', preview: { kind: 'crush', label: 'Hydraulic Slam' } },
  75: { trail: 'gold', preview: { kind: 'trail', label: 'Gold Embers', swatch: '#ffd166' } },
  80: { bg: 'subway', preview: { kind: 'board', label: 'Subway Board', swatch: '#101820' } },
  85: { outfit: 'visor', preview: { kind: 'outfit', label: 'Night Visor' } },
  90: { scrap: 400, preview: { kind: 'scrap', label: '400 Scrap' } },
  95: { emote: 'dumpster_dive', preview: { kind: 'emote', label: 'Dumpster Dive' } },
  100: { scrap: 500, preview: { kind: 'scrap', label: 'Finale Scrap Stash' } },
};

/** Premium track — must pay back MORE gems than PREMIUM_GEM_COST across the season. */
const PREMIUM_LANDMARKS = {
  1: { gems: 25, scrap: 80, preview: { kind: 'gems', label: '25 Gems' } },
  5: { trail: 'lime', preview: { kind: 'trail', label: 'Lime Static', swatch: '#7dff6b' } },
  8: { gems: 30, preview: { kind: 'gems', label: '30 Gems' } },
  10: { outfit: 'hardhat', animated: true, preview: { kind: 'outfit', label: 'Dock Hardhat', animated: true } },
  12: { gems: 25, preview: { kind: 'gems', label: '25 Gems' } },
  15: { crushFx: 'neon_pulse', preview: { kind: 'crush', label: 'Neon Pulse Crush' } },
  18: { gems: 30, preview: { kind: 'gems', label: '30 Gems' } },
  20: { skin: 'gold', preview: { kind: 'skin', label: 'Gold Blocks', swatch: '#ffd166' } },
  25: {
    legendaryStyle: 'neon_legend_base',
    preview: { kind: 'style', label: 'Legend Style: Base Glow', parent: 'neon_legend_raccoon' },
  },
  28: { gems: 35, preview: { kind: 'gems', label: '35 Gems' } },
  30: { banner: 'premium_ribbon', preview: { kind: 'banner', label: 'Premium Ribbon' } },
  35: { gems: 40, preview: { kind: 'gems', label: '40 Gems' } },
  40: { emote: 'raccoon_spin', preview: { kind: 'emote', label: 'Raccoon Spin' } },
  45: { gems: 40, preview: { kind: 'gems', label: '40 Gems' } },
  50: {
    legendaryStyle: 'neon_legend_stripes',
    skinSet: 'neon_alloy',
    preview: { kind: 'style', label: 'Legend Style: Stripes', parent: 'neon_legend_raccoon' },
  },
  55: { gems: 45, preview: { kind: 'gems', label: '45 Gems' } },
  60: { crushFx: 'rainbow_press', preview: { kind: 'crush', label: 'Rainbow Press' } },
  65: { gems: 50, preview: { kind: 'gems', label: '50 Gems' } },
  70: { bg: 'neon_yard', preview: { kind: 'board', label: 'Neon Yard Board', swatch: '#120828' } },
  75: {
    legendaryStyle: 'neon_legend_chrome',
    preview: { kind: 'style', label: 'Legend Style: Chrome', parent: 'neon_legend_raccoon' },
  },
  80: { gems: 55, preview: { kind: 'gems', label: '55 Gems' } },
  85: { trail: 'aurora', preview: { kind: 'trail', label: 'Aurora Trail', swatch: '#a78bfa' } },
  90: { gems: 60, preview: { kind: 'gems', label: '60 Gems' } },
  95: { emote: 'legendary_pose', preview: { kind: 'emote', label: 'Legendary Pose' } },
  100: {
    gems: 80,
    outfit: 'neon_legend_raccoon',
    animated: true,
    legendary: true,
    styles: ['neon_legend_base', 'neon_legend_stripes', 'neon_legend_chrome', 'neon_legend_finale'],
    preview: {
      kind: 'legendary',
      label: 'Neon Legend Raccoon',
      animated: true,
      styles: 4,
    },
  },
};

function fillerFree(at) {
  if (at % 7 === 0) {
    const n = 40 + Math.floor(at / 2);
    return { scrap: n, preview: { kind: 'scrap', label: `${n} Scrap` } };
  }
  if (at % 11 === 0) return { scrap: 60, preview: { kind: 'scrap', label: '60 Scrap' } };
  const n = 25 + (at % 5) * 5;
  return { scrap: n, preview: { kind: 'scrap', label: `${n} Scrap` } };
}

function fillerPremium(at) {
  if (at % 6 === 0) return { gems: 5, scrap: 40, preview: { kind: 'gems', label: '5 Gems' } };
  if (at % 9 === 0) return { scrap: 90, preview: { kind: 'scrap', label: '90 Scrap' } };
  const n = 50 + (at % 4) * 10;
  return { scrap: n, preview: { kind: 'scrap', label: `${n} Scrap` } };
}

function buildTrack(landmarks, filler) {
  const rows = [];
  for (let at = 1; at <= TIERS; at++) {
    rows.push(landmarks[at] ? { at, ...landmarks[at] } : { at, ...filler(at) });
  }
  return rows;
}

const free = buildTrack(FREE_LANDMARKS, fillerFree);
const premium = buildTrack(PREMIUM_LANDMARKS, fillerPremium);

export const SEASON_1_NEON_DUMPSTER = {
  id: 1,
  slug: 'neon-dumpster',
  name: 'Neon Dumpster',
  label: 'Season 1 — Neon Dumpster',
  seasonId: 1,
  tiers: TIERS,
  minTiers: 50,
  maxTiers: 100,
  xpPerTier: XP_PER_TIER,
  theme: {
    tagline: 'Night shift on the glowing docks.',
    primary: '#00f5ff',
    accent: '#ff2bd6',
  },
  xpSources: ['runs', 'daily_challenges', 'weekly_challenges'],
  /** IAP / gem unlock for premium track (~$9.99). */
  premiumPurchase: {
    priceUsd: 9.99,
    gemCost: PREMIUM_GEM_COST,
    productId: '',
    stub: true,
    label: 'Premium Pass',
  },
  /** Stubbed bundle: unlock premium + skip ahead 25 tiers. */
  bundle: {
    id: 'pass_plus_25',
    label: 'Pass + 25 tiers',
    priceUsd: 14.99,
    gemCost: 700,
    tierSkip: 25,
    productId: '',
    stub: true,
  },
  /** Optional gem tier skips — in pass UI only, never auto-pushed. */
  tierBuy: {
    enabled: true,
    gemsPerTier: 50,
    neverPushed: true,
    maxBuyPerSession: 10,
  },
  free,
  premium,
  legendary: {
    at: 100,
    track: 'premium',
    id: 'neon_legend_raccoon',
    kind: 'outfit',
    animated: true,
    label: 'Neon Legend Raccoon',
    styles: [
      { id: 'neon_legend_base', unlockAt: 25, label: 'Base Glow' },
      { id: 'neon_legend_stripes', unlockAt: 50, label: 'Stripes' },
      { id: 'neon_legend_chrome', unlockAt: 75, label: 'Chrome' },
      { id: 'neon_legend_finale', unlockAt: 100, label: 'Finale Pulse' },
    ],
  },
  // Back-compat aliases for older SEASON_PASS readers
  premiumProductId: '',
  premiumPriceUsd: 9.99,
};

export default SEASON_1_NEON_DUMPSTER;
