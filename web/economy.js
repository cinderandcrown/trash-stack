(() => {
  var __defProp = Object.defineProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };

  // src/seasons/season-1-neon-dumpster.js
  var TIERS = 100;
  var XP_PER_TIER = 100;
  var PREMIUM_GEM_COST = 450;
  var FREE_LANDMARKS = {
    1: { scrap: 50, preview: { kind: "scrap", label: "50 Scrap" } },
    5: { trail: "cyan", preview: { kind: "trail", label: "Cyan Sparks", swatch: "#00f5ff" } },
    10: { bg: "rooftop", preview: { kind: "board", label: "Rooftop Board", swatch: "#1a2040" } },
    15: { banner: "dock_flag", preview: { kind: "banner", label: "Dock Flag" } },
    20: { skin: "glass", preview: { kind: "skin", label: "Glass Blocks", swatch: "#9ef6ff" } },
    25: { emote: "wave", preview: { kind: "emote", label: "Wave Emote" } },
    30: { crushFx: "spark_pop", preview: { kind: "crush", label: "Spark Crush" } },
    35: { scrap: 200, preview: { kind: "scrap", label: "200 Scrap" } },
    40: { trail: "mag", preview: { kind: "trail", label: "Magenta Dust", swatch: "#ff2bd6" } },
    45: { outfit: "hoodie", preview: { kind: "outfit", label: "Neon Hoodie" } },
    50: { bg: "alley", preview: { kind: "board", label: "Alley Board", swatch: "#241018" } },
    55: { banner: "neon_strip", preview: { kind: "banner", label: "Neon Strip Banner" } },
    60: { skinSet: "pipe_kit", preview: { kind: "skinSet", label: "Pipe Kit Blocks" } },
    65: { emote: "flex", preview: { kind: "emote", label: "Flex Emote" } },
    70: { crushFx: "hydraulic", preview: { kind: "crush", label: "Hydraulic Slam" } },
    75: { trail: "gold", preview: { kind: "trail", label: "Gold Embers", swatch: "#ffd166" } },
    80: { bg: "subway", preview: { kind: "board", label: "Subway Board", swatch: "#101820" } },
    85: { outfit: "visor", preview: { kind: "outfit", label: "Night Visor" } },
    90: { scrap: 400, preview: { kind: "scrap", label: "400 Scrap" } },
    95: { emote: "dumpster_dive", preview: { kind: "emote", label: "Dumpster Dive" } },
    100: { scrap: 500, preview: { kind: "scrap", label: "Finale Scrap Stash" } }
  };
  var PREMIUM_LANDMARKS = {
    1: { gems: 25, scrap: 80, preview: { kind: "gems", label: "25 Gems" } },
    5: { trail: "lime", preview: { kind: "trail", label: "Lime Static", swatch: "#7dff6b" } },
    8: { gems: 30, preview: { kind: "gems", label: "30 Gems" } },
    10: { outfit: "hardhat", animated: true, preview: { kind: "outfit", label: "Dock Hardhat", animated: true } },
    12: { gems: 25, preview: { kind: "gems", label: "25 Gems" } },
    15: { crushFx: "neon_pulse", preview: { kind: "crush", label: "Neon Pulse Crush" } },
    18: { gems: 30, preview: { kind: "gems", label: "30 Gems" } },
    20: { skin: "gold", preview: { kind: "skin", label: "Gold Blocks", swatch: "#ffd166" } },
    25: {
      legendaryStyle: "neon_legend_base",
      preview: { kind: "style", label: "Legend Style: Base Glow", parent: "neon_legend_raccoon" }
    },
    28: { gems: 35, preview: { kind: "gems", label: "35 Gems" } },
    30: { banner: "premium_ribbon", preview: { kind: "banner", label: "Premium Ribbon" } },
    35: { gems: 40, preview: { kind: "gems", label: "40 Gems" } },
    40: { emote: "raccoon_spin", preview: { kind: "emote", label: "Raccoon Spin" } },
    45: { gems: 40, preview: { kind: "gems", label: "40 Gems" } },
    50: {
      legendaryStyle: "neon_legend_stripes",
      skinSet: "neon_alloy",
      preview: { kind: "style", label: "Legend Style: Stripes", parent: "neon_legend_raccoon" }
    },
    55: { gems: 45, preview: { kind: "gems", label: "45 Gems" } },
    60: { crushFx: "rainbow_press", preview: { kind: "crush", label: "Rainbow Press" } },
    65: { gems: 50, preview: { kind: "gems", label: "50 Gems" } },
    70: { bg: "neon_yard", preview: { kind: "board", label: "Neon Yard Board", swatch: "#120828" } },
    75: {
      legendaryStyle: "neon_legend_chrome",
      preview: { kind: "style", label: "Legend Style: Chrome", parent: "neon_legend_raccoon" }
    },
    80: { gems: 55, preview: { kind: "gems", label: "55 Gems" } },
    85: { trail: "aurora", preview: { kind: "trail", label: "Aurora Trail", swatch: "#a78bfa" } },
    90: { gems: 60, preview: { kind: "gems", label: "60 Gems" } },
    95: { emote: "legendary_pose", preview: { kind: "emote", label: "Legendary Pose" } },
    100: {
      gems: 80,
      outfit: "neon_legend_raccoon",
      animated: true,
      legendary: true,
      styles: ["neon_legend_base", "neon_legend_stripes", "neon_legend_chrome", "neon_legend_finale"],
      preview: {
        kind: "legendary",
        label: "Neon Legend Raccoon",
        animated: true,
        styles: 4
      }
    }
  };
  function fillerFree(at) {
    if (at % 7 === 0) {
      const n2 = 40 + Math.floor(at / 2);
      return { scrap: n2, preview: { kind: "scrap", label: `${n2} Scrap` } };
    }
    if (at % 11 === 0) return { scrap: 60, preview: { kind: "scrap", label: "60 Scrap" } };
    const n = 25 + at % 5 * 5;
    return { scrap: n, preview: { kind: "scrap", label: `${n} Scrap` } };
  }
  function fillerPremium(at) {
    if (at % 6 === 0) return { gems: 5, scrap: 40, preview: { kind: "gems", label: "5 Gems" } };
    if (at % 9 === 0) return { scrap: 90, preview: { kind: "scrap", label: "90 Scrap" } };
    const n = 50 + at % 4 * 10;
    return { scrap: n, preview: { kind: "scrap", label: `${n} Scrap` } };
  }
  function buildTrack(landmarks, filler) {
    const rows = [];
    for (let at = 1; at <= TIERS; at++) {
      rows.push(landmarks[at] ? { at, ...landmarks[at] } : { at, ...filler(at) });
    }
    return rows;
  }
  var free = buildTrack(FREE_LANDMARKS, fillerFree);
  var premium = buildTrack(PREMIUM_LANDMARKS, fillerPremium);
  var SEASON_1_NEON_DUMPSTER = {
    id: 1,
    slug: "neon-dumpster",
    name: "Neon Dumpster",
    label: "Season 1 \u2014 Neon Dumpster",
    seasonId: 1,
    tiers: TIERS,
    minTiers: 50,
    maxTiers: 100,
    xpPerTier: XP_PER_TIER,
    theme: {
      tagline: "Night shift on the glowing docks.",
      primary: "#00f5ff",
      accent: "#ff2bd6"
    },
    xpSources: ["runs", "daily_challenges", "weekly_challenges"],
    /** IAP / gem unlock for premium track (~$9.99). */
    premiumPurchase: {
      priceUsd: 9.99,
      gemCost: PREMIUM_GEM_COST,
      productId: "",
      stub: true,
      label: "Premium Pass"
    },
    /** Stubbed bundle: unlock premium + skip ahead 25 tiers. */
    bundle: {
      id: "pass_plus_25",
      label: "Pass + 25 tiers",
      priceUsd: 14.99,
      gemCost: 700,
      tierSkip: 25,
      productId: "",
      stub: true
    },
    /** Optional gem tier skips — in pass UI only, never auto-pushed. */
    tierBuy: {
      enabled: true,
      gemsPerTier: 50,
      neverPushed: true,
      maxBuyPerSession: 10
    },
    free,
    premium,
    legendary: {
      at: 100,
      track: "premium",
      id: "neon_legend_raccoon",
      kind: "outfit",
      animated: true,
      label: "Neon Legend Raccoon",
      styles: [
        { id: "neon_legend_base", unlockAt: 25, label: "Base Glow" },
        { id: "neon_legend_stripes", unlockAt: 50, label: "Stripes" },
        { id: "neon_legend_chrome", unlockAt: 75, label: "Chrome" },
        { id: "neon_legend_finale", unlockAt: 100, label: "Finale Pulse" }
      ]
    },
    // Back-compat aliases for older SEASON_PASS readers
    premiumProductId: "",
    premiumPriceUsd: 9.99
  };

  // src/seasons/index.js
  var SEASONS = {
    [SEASON_1_NEON_DUMPSTER.id]: SEASON_1_NEON_DUMPSTER,
    [SEASON_1_NEON_DUMPSTER.slug]: SEASON_1_NEON_DUMPSTER
  };
  var ACTIVE_SEASON_ID = 1;
  function getSeason(id = ACTIVE_SEASON_ID) {
    return SEASONS[id] || SEASON_1_NEON_DUMPSTER;
  }

  // src/economy-config.js
  var ECONOMY_VERSION = 3;
  var SOFT = {
    id: "scrap",
    label: "Scrap",
    symbol: "\u2699",
    startAmount: 80
  };
  var PREMIUM = {
    id: "gems",
    label: "Neon Gems",
    symbol: "\u25C6",
    startAmount: 20,
    rareEarnPerRunCap: 2
  };
  var GEM_PACKS = [
    { id: "gems_40", gems: 40, priceUsd: 0.99, productId: "", badge: null },
    { id: "gems_210", gems: 210, priceUsd: 4.99, productId: "", badge: "Popular" },
    { id: "gems_450", gems: 450, priceUsd: 9.99, productId: "", badge: null },
    { id: "gems_1200", gems: 1200, priceUsd: 19.99, productId: "", badge: "Best value" },
    { id: "gems_2500", gems: 2500, priceUsd: 49.99, productId: "", badge: null }
  ];
  var STARTER_PACK = {
    id: "starter_pack",
    label: "Dock Starter Pack",
    gems: 120,
    scrap: 500,
    trail: "cyan",
    priceUsd: 2.99,
    productId: "",
    oneTime: true
  };
  var ONE_TIME_OFFER = {
    enabled: true,
    /** At most one special-offer card per play session. */
    maxPerSession: 1,
    /** Once dismissed, never re-show that calendar day. */
    maxSurfacesPerDay: 1,
    neverReshowSameDay: true,
    cooldownHours: 48,
    quietHours: { start: 21, end: 8 },
    /** Only after a win or level-up — never launch / mid-run / after loss. */
    allowContexts: ["after_win", "after_level_up"],
    denyContexts: ["launch", "mid_run", "after_loss"],
    /** Offers live in Shop or as one small dismissible badge — not blocking popups. */
    placements: ["shop", "dismissible_badge"],
    dismissOneTap: true,
    fakeCountdownTimers: false,
    confirmshaming: false,
    bannedCopyPatterns: ["no thanks, i like losing", "don't miss out", "last chance"],
    copy: "Optional offer \u2014 never required to play.",
    rewardedAdsOptInOnly: true,
    freeToPlayComplete: true,
    premiumShowcase: {
      leaderboardOtherSkins: true,
      passPreviews: true,
      tryForOneRun: true
    }
  };
  var BUILDINGS = {
    recycler: {
      id: "recycler",
      name: "Recycler",
      blurb: "Bonus Scrap from recycle pops.",
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
        { cost: 4e3, sec: 14400, perk: { scrapRecycleBonus: 0.4 } }
      ]
    },
    compactor: {
      id: "compactor",
      name: "Compactor",
      blurb: "Bonus Scrap from row crushes (cosmetic juice too).",
      maxLevel: 8,
      levels: [
        { cost: 0, sec: 0, perk: { scrapClearBonus: 0 } },
        { cost: 150, sec: 90, perk: { scrapClearBonus: 0.05 } },
        { cost: 320, sec: 240, perk: { scrapClearBonus: 0.1 } },
        { cost: 600, sec: 900, perk: { scrapClearBonus: 0.15 } },
        { cost: 1e3, sec: 2400, perk: { scrapClearBonus: 0.2 } },
        { cost: 1700, sec: 4800, perk: { scrapClearBonus: 0.25 } },
        { cost: 2800, sec: 9600, perk: { scrapClearBonus: 0.3 } },
        { cost: 4500, sec: 18e3, perk: { scrapClearBonus: 0.4 } }
      ]
    },
    neonSign: {
      id: "neonSign",
      name: "Neon Sign",
      blurb: "Cosmetic board glow + tiny XP bonus (not score P2W).",
      maxLevel: 6,
      levels: [
        { cost: 0, sec: 0, perk: { xpBonus: 0, glow: 0 } },
        { cost: 200, sec: 120, perk: { xpBonus: 0.05, glow: 1 } },
        { cost: 450, sec: 600, perk: { xpBonus: 0.08, glow: 2 } },
        { cost: 800, sec: 1800, perk: { xpBonus: 0.1, glow: 3 } },
        { cost: 1400, sec: 5400, perk: { xpBonus: 0.12, glow: 4 } },
        { cost: 2200, sec: 10800, perk: { xpBonus: 0.15, glow: 5 } }
      ]
    },
    stashVault: {
      id: "stashVault",
      name: "Stash Vault",
      blurb: "Extra chest slot + shorter chest timers.",
      maxLevel: 5,
      levels: [
        { cost: 0, sec: 0, perk: { chestSlots: 2, chestTimeMult: 1 } },
        { cost: 250, sec: 300, perk: { chestSlots: 3, chestTimeMult: 0.95 } },
        { cost: 700, sec: 1800, perk: { chestSlots: 3, chestTimeMult: 0.9 } },
        { cost: 1600, sec: 7200, perk: { chestSlots: 4, chestTimeMult: 0.85 } },
        { cost: 3200, sec: 14400, perk: { chestSlots: 4, chestTimeMult: 0.75 } }
      ]
    }
  };
  var BUILDERS = {
    freeSlots: 2,
    gemUnlockSlotCost: 350,
    maxSlots: 4
  };
  var SPEEDUP = {
    secPerGem: 60,
    minGems: 1,
    maxGemsPerAction: 200
  };
  var SEASON_PASS = getSeason(ACTIVE_SEASON_ID);
  var CHESTS = {
    dock_crate: {
      id: "dock_crate",
      name: "Dock Crate",
      unlockSec: 30 * 60,
      earnWeight: 70,
      slots: true,
      odds: [
        { label: "40 Scrap", kind: "scrap", n: 40, pct: 35 },
        { label: "80 Scrap", kind: "scrap", n: 80, pct: 25 },
        { label: "120 Scrap", kind: "scrap", n: 120, pct: 15 },
        { label: "2 Gems", kind: "gems", n: 2, pct: 10 },
        { label: "5 Gems", kind: "gems", n: 5, pct: 5 },
        { label: "Cosmetic LOOK", kind: "cosmetic", n: 0, pct: 10 }
      ]
    },
    neon_crate: {
      id: "neon_crate",
      name: "Neon Crate",
      unlockSec: 3 * 60 * 60,
      earnWeight: 25,
      slots: true,
      odds: [
        { label: "100 Scrap", kind: "scrap", n: 100, pct: 30 },
        { label: "200 Scrap", kind: "scrap", n: 200, pct: 25 },
        { label: "5 Gems", kind: "gems", n: 5, pct: 20 },
        { label: "12 Gems", kind: "gems", n: 12, pct: 10 },
        { label: "Cosmetic LOOK", kind: "cosmetic", n: 0, pct: 15 }
      ]
    },
    legend_crate: {
      id: "legend_crate",
      name: "Legend Crate",
      unlockSec: 8 * 60 * 60,
      earnWeight: 5,
      slots: true,
      odds: [
        { label: "250 Scrap", kind: "scrap", n: 250, pct: 25 },
        { label: "400 Scrap", kind: "scrap", n: 400, pct: 20 },
        { label: "15 Gems", kind: "gems", n: 15, pct: 25 },
        { label: "30 Gems", kind: "gems", n: 30, pct: 15 },
        { label: "Rare LOOK", kind: "cosmetic", n: 0, pct: 15 }
      ]
    }
  };
  var LOGIN_STREAK = {
    capScrap: 120,
    formulaNote: "min(cap, 5*day + 20*floor(day/7))",
    freezeCostGems: 15,
    freezeMaxOwned: 2
  };
  var SPIN = {
    freePerDay: 1,
    rewardedExtraPerDay: 1,
    oddsEqualSlices: true
  };
  var NOTIFICATIONS = {
    askAfterFirstWin: true,
    neverAtLaunch: true,
    maxPerDay: 2,
    quietHours: { start: 21, end: 8 },
    kinds: ["upgrade_done", "chest_ready", "daily_reward", "streak_risk", "new_season"]
  };
  var ADS = {
    interstitialEveryNOvers: 3,
    interstitialSkipFirstRuns: 2,
    bannersInPlay: false,
    rewarded: ["revive", "double", "spin", "chest_speed"]
  };
  var REMOVE_ADS = {
    productId: "",
    priceUsd: 4.99,
    stub: true
  };
  var COMPLIANCE = {
    maxAgeRating: "12+",
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
    freeToPlayComplete: true
  };
  function attachEconomyGlobal(target = globalThis) {
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
      ACTIVE_SEASON_ID,
      CHESTS,
      LOGIN_STREAK,
      SPIN,
      NOTIFICATIONS,
      ADS,
      REMOVE_ADS,
      COMPLIANCE
    };
  }
  attachEconomyGlobal();

  // src/economy-math.js
  var economy_math_exports = {};
  __export(economy_math_exports, {
    aggregatePerks: () => aggregatePerks,
    applyBuyTiers: () => applyBuyTiers,
    applyScrapGain: () => applyScrapGain,
    applyStartUpgrade: () => applyStartUpgrade,
    applyXpGain: () => applyXpGain,
    assertOddsSum100: () => assertOddsSum100,
    assertOfferFrequencyCaps: () => assertOfferFrequencyCaps,
    assertSeasonPassShape: () => assertSeasonPassShape,
    buildingPerk: () => buildingPerk,
    calendarDayKey: () => calendarDayKey,
    canEnqueueChest: () => canEnqueueChest,
    canStartUpgrade: () => canStartUpgrade,
    canSurfaceSpecialOffer: () => canSurfaceSpecialOffer,
    chestUnlockMs: () => chestUnlockMs,
    completeReadyUpgrades: () => completeReadyUpgrades,
    enqueueChest: () => enqueueChest,
    formatOddsLine: () => formatOddsLine,
    gemsForReadyAt: () => gemsForReadyAt,
    gemsForSpeedup: () => gemsForSpeedup,
    gemsToBuyTiers: () => gemsToBuyTiers,
    isConfirmshamingCopy: () => isConfirmshamingCopy,
    loginStreakScrap: () => loginStreakScrap,
    migrateLegacySave: () => migrateLegacySave,
    openChestIfReady: () => openChestIfReady,
    pickWeightedChest: () => pickWeightedChest,
    premiumGemPayback: () => premiumGemPayback,
    recordSpecialOfferDismiss: () => recordSpecialOfferDismiss,
    recordSpecialOfferSurface: () => recordSpecialOfferSurface,
    rollChestReward: () => rollChestReward,
    seasonTierUnlocked: () => seasonTierUnlocked,
    speedupChest: () => speedupChest,
    speedupQueueItem: () => speedupQueueItem,
    sumTrackGems: () => sumTrackGems,
    upgradeCost: () => upgradeCost,
    validateChestTables: () => validateChestTables
  });
  function assertOddsSum100(odds, label = "odds") {
    const sum = odds.reduce((a, o) => a + o.pct, 0);
    if (Math.abs(sum - 100) > 0.01) {
      throw new Error(`${label} must sum to 100, got ${sum}`);
    }
    return true;
  }
  function validateChestTables(chests = CHESTS) {
    for (const c of Object.values(chests)) {
      assertOddsSum100(c.odds, c.id);
      if (!COMPLIANCE.showOddsForRandom) throw new Error("odds required");
    }
    return true;
  }
  function upgradeCost(buildingId, fromLevel) {
    const b = BUILDINGS[buildingId];
    if (!b) throw new Error("unknown building " + buildingId);
    const next = fromLevel + 1;
    if (next > b.maxLevel) return null;
    const row = b.levels[next - 1];
    return { scrap: row.cost, sec: row.sec, perk: row.perk, toLevel: next };
  }
  function buildingPerk(buildingId, level) {
    const b = BUILDINGS[buildingId];
    if (!b) return {};
    const lv = Math.max(1, Math.min(b.maxLevel, level || 1));
    return { ...b.levels[lv - 1].perk || {} };
  }
  function aggregatePerks(baseLevels) {
    const out = {
      scrapRecycleBonus: 0,
      scrapClearBonus: 0,
      xpBonus: 0,
      glow: 0,
      chestSlots: BUILDINGS.stashVault.levels[0].perk.chestSlots,
      chestTimeMult: 1
    };
    for (const id of Object.keys(BUILDINGS)) {
      const perk = buildingPerk(id, baseLevels && baseLevels[id] || 1);
      for (const [k, v] of Object.entries(perk)) {
        if (k === "chestSlots") out.chestSlots = v;
        else if (k === "chestTimeMult") out.chestTimeMult = v;
        else if (typeof v === "number") out[k] = (out[k] || 0) + v;
        else out[k] = v;
      }
    }
    return out;
  }
  function gemsForSpeedup(remainingMs, now = Date.now()) {
    const rem = Math.max(0, remainingMs);
    if (rem <= 0) return 0;
    const sec = Math.ceil(rem / 1e3);
    const gems = Math.ceil(sec / SPEEDUP.secPerGem);
    return Math.min(SPEEDUP.maxGemsPerAction, Math.max(SPEEDUP.minGems, gems));
  }
  function gemsForReadyAt(readyAt, now = Date.now()) {
    return gemsForSpeedup(readyAt - now, now);
  }
  function canStartUpgrade(state, buildingId) {
    const levels = state.base?.levels || {};
    const from = levels[buildingId] || 1;
    const cost = upgradeCost(buildingId, from);
    if (!cost) return { ok: false, reason: "max" };
    const busy = (state.base?.queue || []).filter((q) => q.readyAt > Date.now());
    const slots = state.base?.builderSlots ?? BUILDERS.freeSlots;
    if (busy.length >= slots) return { ok: false, reason: "builders" };
    if ((state.scrap || 0) < cost.scrap) return { ok: false, reason: "scrap" };
    return { ok: true, cost };
  }
  function applyStartUpgrade(state, buildingId, now = Date.now()) {
    const check = canStartUpgrade(state, buildingId);
    if (!check.ok) return { ok: false, reason: check.reason, state };
    const next = {
      ...state,
      scrap: state.scrap - check.cost.scrap,
      base: {
        ...state.base,
        levels: { ...state.base?.levels || {} },
        queue: [...state.base?.queue || []]
      }
    };
    next.base.queue.push({
      buildingId,
      from: next.base.levels[buildingId] || 1,
      to: check.cost.toLevel,
      startedAt: now,
      readyAt: now + check.cost.sec * 1e3
    });
    return { ok: true, state: next };
  }
  function completeReadyUpgrades(state, now = Date.now()) {
    const queue = state.base?.queue || [];
    const still = [];
    const levels = { ...state.base?.levels || {} };
    let completed = [];
    for (const q of queue) {
      if (q.readyAt <= now) {
        levels[q.buildingId] = q.to;
        completed.push(q);
      } else still.push(q);
    }
    if (!completed.length) return { state, completed: [] };
    return {
      state: { ...state, base: { ...state.base, levels, queue: still } },
      completed
    };
  }
  function speedupQueueItem(state, index, now = Date.now()) {
    const queue = [...state.base?.queue || []];
    const item = queue[index];
    if (!item) return { ok: false, reason: "missing" };
    const cost = gemsForReadyAt(item.readyAt, now);
    if ((state.gems || 0) < cost) return { ok: false, reason: "gems", cost };
    item.readyAt = now;
    const afterPay = { ...state, gems: state.gems - cost, base: { ...state.base, queue } };
    return { ok: true, cost, ...completeReadyUpgrades(afterPay, now) };
  }
  function seasonTierUnlocked(xp, xpPerTier = SEASON_PASS.xpPerTier, max = SEASON_PASS.tiers) {
    return Math.min(max, Math.max(0, Math.floor((xp || 0) / xpPerTier)));
  }
  function sumTrackGems(track = SEASON_PASS.premium) {
    return (track || []).reduce((a, row) => a + (row.gems || 0), 0);
  }
  function premiumGemPayback(season = SEASON_PASS) {
    const cost = season.premiumPurchase?.gemCost ?? season.premiumGemCost ?? 0;
    const earned = sumTrackGems(season.premium);
    return { cost, earned, surplus: earned - cost, paysBack: earned > cost };
  }
  function assertSeasonPassShape(season = SEASON_PASS) {
    const tiers = season.tiers | 0;
    if (tiers < 50 || tiers > 100) throw new Error(`season tiers must be 50\u2013100, got ${tiers}`);
    if (!season.free || season.free.length !== tiers) throw new Error("free track length mismatch");
    if (!season.premium || season.premium.length !== tiers) throw new Error("premium track length mismatch");
    if (!season.name) throw new Error("season needs a themed name");
    if (!season.legendary || season.legendary.at !== tiers) throw new Error("tier-max legendary required");
    if (!Array.isArray(season.legendary.styles) || season.legendary.styles.length < 2) {
      throw new Error("legendary needs progressive styles");
    }
    const pay = premiumGemPayback(season);
    if (!pay.paysBack) throw new Error(`premium gems ${pay.earned} must exceed cost ${pay.cost}`);
    if (!season.bundle || season.bundle.tierSkip !== 25) throw new Error("Pass + 25 tiers bundle stub required");
    if (!season.tierBuy || season.tierBuy.neverPushed !== true) throw new Error("tierBuy must be optional/never pushed");
    if (!Array.isArray(season.xpSources) || !season.xpSources.includes("runs")) {
      throw new Error("xpSources must include runs + challenges");
    }
    return true;
  }
  function gemsToBuyTiers(n, season = SEASON_PASS) {
    const per = season.tierBuy?.gemsPerTier ?? 50;
    const count = Math.max(0, n | 0);
    return count * per;
  }
  function applyBuyTiers(state, n, now = Date.now(), season = SEASON_PASS) {
    if (!season.tierBuy?.enabled) return { ok: false, reason: "disabled" };
    const count = Math.max(0, n | 0);
    if (!count) return { ok: false, reason: "zero" };
    const cost = gemsToBuyTiers(count, season);
    if ((state.gems || 0) < cost) return { ok: false, reason: "gems", cost };
    const xpGain = count * (season.xpPerTier || 100);
    return {
      ok: true,
      cost,
      state: {
        ...state,
        gems: state.gems - cost,
        battlePass: {
          ...state.battlePass || {},
          xp: (state.battlePass?.xp || 0) + xpGain,
          tiersBought: (state.battlePass?.tiersBought || 0) + count,
          lastTierBuyAt: now
        }
      }
    };
  }
  function loginStreakScrap(day, cfg = LOGIN_STREAK) {
    const d = Math.max(1, day | 0);
    return Math.min(cfg.capScrap, 5 * d + 20 * Math.floor(d / 7));
  }
  function pickWeightedChest(rng = Math.random, chests = CHESTS) {
    const list = Object.values(chests);
    const total = list.reduce((a, c) => a + c.earnWeight, 0);
    let r = rng() * total;
    for (const c of list) {
      r -= c.earnWeight;
      if (r <= 0) return c.id;
    }
    return list[list.length - 1].id;
  }
  function rollChestReward(chestId, rng = Math.random, chests = CHESTS) {
    const chest = chests[chestId];
    if (!chest) throw new Error("unknown chest");
    assertOddsSum100(chest.odds, chestId);
    let r = rng() * 100;
    for (const o of chest.odds) {
      r -= o.pct;
      if (r <= 0) return { ...o, chestId };
    }
    return { ...chest.odds[chest.odds.length - 1], chestId };
  }
  function chestUnlockMs(chestId, perks, chests = CHESTS) {
    const c = chests[chestId];
    const mult = perks?.chestTimeMult ?? 1;
    return Math.floor(c.unlockSec * 1e3 * mult);
  }
  function canEnqueueChest(state, perks) {
    const slots = perks?.chestSlots ?? 2;
    const active = (state.chests || []).filter((c) => !c.opened);
    return active.length < slots;
  }
  function enqueueChest(state, chestId, now = Date.now(), perks = aggregatePerks(state.base?.levels)) {
    if (!canEnqueueChest(state, perks)) return { ok: false, reason: "slots" };
    const unlockMs = chestUnlockMs(chestId, perks);
    const chest = {
      id: `${chestId}_${now}`,
      chestId,
      earnedAt: now,
      readyAt: now + unlockMs,
      opened: false
    };
    return { ok: true, state: { ...state, chests: [...state.chests || [], chest] } };
  }
  function speedupChest(state, chestKey, now = Date.now()) {
    const chests = (state.chests || []).map((c) => ({ ...c }));
    const idx = chests.findIndex((c) => c.id === chestKey);
    if (idx < 0) return { ok: false, reason: "missing" };
    const cost = gemsForReadyAt(chests[idx].readyAt, now);
    if ((state.gems || 0) < cost) return { ok: false, reason: "gems", cost };
    chests[idx].readyAt = now;
    return { ok: true, cost, state: { ...state, gems: state.gems - cost, chests } };
  }
  function openChestIfReady(state, chestKey, now = Date.now(), rng = Math.random) {
    const chests = (state.chests || []).map((c2) => ({ ...c2 }));
    const idx = chests.findIndex((c2) => c2.id === chestKey);
    if (idx < 0) return { ok: false, reason: "missing" };
    const c = chests[idx];
    if (c.opened) return { ok: false, reason: "opened" };
    if (c.readyAt > now) return { ok: false, reason: "locked", readyAt: c.readyAt };
    const reward = rollChestReward(c.chestId, rng);
    c.opened = true;
    c.openedAt = now;
    c.reward = reward;
    let next = { ...state, chests };
    if (reward.kind === "scrap") next.scrap = (next.scrap || 0) + reward.n;
    if (reward.kind === "gems") next.gems = (next.gems || 0) + reward.n;
    return { ok: true, reward, state: next };
  }
  function formatOddsLine(odds) {
    return odds.map((o) => `${o.label} ${o.pct}%`).join(" \xB7 ");
  }
  function migrateLegacySave(raw) {
    const s = { ...raw };
    if (s.scrap == null && s.shinies != null) s.scrap = s.shinies;
    if (s.gems == null) s.gems = 20;
    if (!s.base) {
      s.base = {
        levels: { recycler: 1, compactor: 1, neonSign: 1, stashVault: 1 },
        queue: [],
        builderSlots: BUILDERS.freeSlots
      };
    }
    if (!s.chests) s.chests = [];
    if (!s.collection) s.collection = { skins: [], trails: [], bgs: [], outfits: [] };
    if (!s.notif) {
      s.notif = {
        permission: "default",
        asked: false,
        enabled: { upgrade_done: true, chest_ready: true, daily_reward: true, streak_risk: true, new_season: true },
        quietHours: true,
        sentToday: 0,
        sentDate: ""
      };
    }
    if (!s.iap) s.iap = {};
    s.iap.starterBought = !!s.iap.starterBought;
    s.iap.removeAds = !!s.adsRemoved;
    if (!s.offer) {
      s.offer = { sessionSurfaces: 0, daySurfaces: 0, dayKey: "", dismissedDay: "" };
    }
    if (!s.battlePass) s.battlePass = { season: SEASON_PASS.seasonId, xp: 0, claimedFree: [], claimedPremium: [] };
    if (s.battlePass.premium == null) s.battlePass.premium = !!s.premiumPass;
    if (s.streakFreeze == null) s.streakFreeze = 0;
    s.shinies = s.scrap;
    return s;
  }
  function applyScrapGain(amount, perks, source) {
    let n = Math.max(0, amount | 0);
    if (source === "recycle" && perks?.scrapRecycleBonus) n = Math.floor(n * (1 + perks.scrapRecycleBonus));
    if (source === "clear" && perks?.scrapClearBonus) n = Math.floor(n * (1 + perks.scrapClearBonus));
    return n;
  }
  function applyXpGain(amount, perks) {
    const n = Math.max(0, amount | 0);
    if (!perks?.xpBonus) return n;
    return Math.floor(n * (1 + perks.xpBonus));
  }
  function calendarDayKey(ms = Date.now()) {
    const d = new Date(ms);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }
  function offerState(state) {
    return state?.offer || state?.iap?.offer || {};
  }
  function canSurfaceSpecialOffer(state, context, now = Date.now(), cfg = ONE_TIME_OFFER) {
    if (!cfg?.enabled) return { ok: false, reason: "disabled" };
    if (!COMPLIANCE.noPurchaseNagging) return { ok: false, reason: "compliance" };
    const deny = cfg.denyContexts || [];
    if (deny.includes(context)) return { ok: false, reason: "denied_context" };
    if (context === "shop") return { ok: true, reason: "shop_catalog" };
    const allow = cfg.allowContexts || [];
    if (!allow.includes(context)) return { ok: false, reason: "context" };
    const o = offerState(state);
    const day = calendarDayKey(now);
    const maxSession = cfg.maxPerSession ?? 1;
    const maxDay = cfg.maxSurfacesPerDay ?? 1;
    if (cfg.neverReshowSameDay && o.dismissedDay === day) return { ok: false, reason: "dismissed_today" };
    if ((o.daySurfaces || 0) >= maxDay && o.dayKey === day) return { ok: false, reason: "day_cap" };
    if ((o.sessionSurfaces || 0) >= maxSession) return { ok: false, reason: "session_cap" };
    if (cfg.cooldownHours && o.lastSurfaceAt) {
      const coolMs = cfg.cooldownHours * 3600 * 1e3;
      if (now - o.lastSurfaceAt < coolMs) {
        return { ok: false, reason: "cooldown" };
      }
    }
    if (cfg.quietHours) {
      const h = new Date(now).getHours();
      const { start, end } = cfg.quietHours;
      const quiet = start > end ? h >= start || h < end : h >= start && h < end;
      if (quiet) return { ok: false, reason: "quiet_hours" };
    }
    return { ok: true, reason: "allowed" };
  }
  function recordSpecialOfferSurface(state, now = Date.now()) {
    const day = calendarDayKey(now);
    const prev = offerState(state);
    const sameDay = prev.dayKey === day;
    const offer = {
      ...prev,
      dayKey: day,
      daySurfaces: sameDay ? (prev.daySurfaces || 0) + 1 : 1,
      sessionSurfaces: (prev.sessionSurfaces || 0) + 1,
      lastSurfaceAt: now
    };
    return { ...state, offer };
  }
  function recordSpecialOfferDismiss(state, now = Date.now()) {
    const day = calendarDayKey(now);
    const prev = offerState(state);
    return {
      ...state,
      offer: {
        ...prev,
        dismissedDay: day,
        dayKey: day,
        lastDismissAt: now
      }
    };
  }
  function assertOfferFrequencyCaps(cfg = ONE_TIME_OFFER) {
    if ((cfg.maxPerSession ?? 0) !== 1) {
      throw new Error("maxPerSession must be 1");
    }
    if ((cfg.maxSurfacesPerDay ?? 0) !== 1) {
      throw new Error("maxSurfacesPerDay must be 1");
    }
    if (cfg.neverReshowSameDay !== true) throw new Error("neverReshowSameDay required");
    if (cfg.fakeCountdownTimers !== false) throw new Error("fakeCountdownTimers must be false");
    if (cfg.confirmshaming !== false) throw new Error("confirmshaming must be false");
    if (cfg.dismissOneTap !== true) throw new Error("dismissOneTap required");
    if (cfg.rewardedAdsOptInOnly !== true) throw new Error("rewarded ads must be opt-in");
    if (cfg.freeToPlayComplete !== true) throw new Error("freeToPlayComplete required");
    const allow = cfg.allowContexts || [];
    if (!allow.includes("after_win") || !allow.includes("after_level_up")) {
      throw new Error("offers only after_win / after_level_up");
    }
    for (const bad of ["launch", "mid_run", "after_loss"]) {
      if (!(cfg.denyContexts || []).includes(bad)) {
        throw new Error(`denyContexts must include ${bad}`);
      }
      if (allow.includes(bad)) throw new Error(`${bad} must not be allowed`);
    }
    if (!(cfg.placements || []).includes("shop") || !(cfg.placements || []).includes("dismissible_badge")) {
      throw new Error("placements must include shop + dismissible_badge");
    }
    return true;
  }
  function isConfirmshamingCopy(text, cfg = ONE_TIME_OFFER) {
    const t = String(text || "").toLowerCase();
    for (const p of cfg.bannedCopyPatterns || []) {
      if (t.includes(String(p).toLowerCase())) return true;
    }
    return false;
  }

  // src/economy-browser.js
  attachEconomyGlobal(globalThis);
  globalThis.TrashEconomy = economy_math_exports;
})();
