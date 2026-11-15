/**
 * Pure economy math — no DOM, safe for unit tests.
 */
import {
  BUILDINGS,
  BUILDERS,
  SPEEDUP,
  SEASON_PASS,
  CHESTS,
  LOGIN_STREAK,
  COMPLIANCE,
} from './economy-config.js';

export function assertOddsSum100(odds, label = 'odds') {
  const sum = odds.reduce((a, o) => a + o.pct, 0);
  if (Math.abs(sum - 100) > 0.01) {
    throw new Error(`${label} must sum to 100, got ${sum}`);
  }
  return true;
}

export function validateChestTables(chests = CHESTS) {
  for (const c of Object.values(chests)) {
    assertOddsSum100(c.odds, c.id);
    if (!COMPLIANCE.showOddsForRandom) throw new Error('odds required');
  }
  return true;
}

export function upgradeCost(buildingId, fromLevel) {
  const b = BUILDINGS[buildingId];
  if (!b) throw new Error('unknown building ' + buildingId);
  const next = fromLevel + 1;
  if (next > b.maxLevel) return null;
  const row = b.levels[next - 1];
  return { scrap: row.cost, sec: row.sec, perk: row.perk, toLevel: next };
}

export function buildingPerk(buildingId, level) {
  const b = BUILDINGS[buildingId];
  if (!b) return {};
  const lv = Math.max(1, Math.min(b.maxLevel, level || 1));
  return { ...(b.levels[lv - 1].perk || {}) };
}

export function aggregatePerks(baseLevels) {
  const out = {
    scrapRecycleBonus: 0,
    scrapClearBonus: 0,
    xpBonus: 0,
    glow: 0,
    chestSlots: BUILDINGS.stashVault.levels[0].perk.chestSlots,
    chestTimeMult: 1,
  };
  for (const id of Object.keys(BUILDINGS)) {
    const perk = buildingPerk(id, (baseLevels && baseLevels[id]) || 1);
    for (const [k, v] of Object.entries(perk)) {
      if (k === 'chestSlots') out.chestSlots = v;
      else if (k === 'chestTimeMult') out.chestTimeMult = v;
      else if (typeof v === 'number') out[k] = (out[k] || 0) + v;
      else out[k] = v;
    }
  }
  return out;
}

/** Gems to finish remainingMs of a timer. */
export function gemsForSpeedup(remainingMs, now = Date.now()) {
  const rem = Math.max(0, remainingMs);
  if (rem <= 0) return 0;
  const sec = Math.ceil(rem / 1000);
  const gems = Math.ceil(sec / SPEEDUP.secPerGem);
  return Math.min(SPEEDUP.maxGemsPerAction, Math.max(SPEEDUP.minGems, gems));
}

export function gemsForReadyAt(readyAt, now = Date.now()) {
  return gemsForSpeedup(readyAt - now, now);
}

export function canStartUpgrade(state, buildingId) {
  const levels = state.base?.levels || {};
  const from = levels[buildingId] || 1;
  const cost = upgradeCost(buildingId, from);
  if (!cost) return { ok: false, reason: 'max' };
  const busy = (state.base?.queue || []).filter((q) => q.readyAt > Date.now());
  const slots = state.base?.builderSlots ?? BUILDERS.freeSlots;
  if (busy.length >= slots) return { ok: false, reason: 'builders' };
  if ((state.scrap || 0) < cost.scrap) return { ok: false, reason: 'scrap' };
  return { ok: true, cost };
}

export function applyStartUpgrade(state, buildingId, now = Date.now()) {
  const check = canStartUpgrade(state, buildingId);
  if (!check.ok) return { ok: false, reason: check.reason, state };
  const next = {
    ...state,
    scrap: state.scrap - check.cost.scrap,
    base: {
      ...state.base,
      levels: { ...(state.base?.levels || {}) },
      queue: [...(state.base?.queue || [])],
    },
  };
  next.base.queue.push({
    buildingId,
    from: next.base.levels[buildingId] || 1,
    to: check.cost.toLevel,
    startedAt: now,
    readyAt: now + check.cost.sec * 1000,
  });
  return { ok: true, state: next };
}

export function completeReadyUpgrades(state, now = Date.now()) {
  const queue = state.base?.queue || [];
  const still = [];
  const levels = { ...(state.base?.levels || {}) };
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
    completed,
  };
}

export function speedupQueueItem(state, index, now = Date.now()) {
  const queue = [...(state.base?.queue || [])];
  const item = queue[index];
  if (!item) return { ok: false, reason: 'missing' };
  const cost = gemsForReadyAt(item.readyAt, now);
  if ((state.gems || 0) < cost) return { ok: false, reason: 'gems', cost };
  item.readyAt = now;
  const afterPay = { ...state, gems: state.gems - cost, base: { ...state.base, queue } };
  return { ok: true, cost, ...completeReadyUpgrades(afterPay, now) };
}

export function seasonTierUnlocked(xp, xpPerTier = SEASON_PASS.xpPerTier, max = SEASON_PASS.tiers) {
  return Math.min(max, Math.max(0, Math.floor((xp || 0) / xpPerTier)));
}

export function loginStreakScrap(day, cfg = LOGIN_STREAK) {
  const d = Math.max(1, day | 0);
  return Math.min(cfg.capScrap, 5 * d + 20 * Math.floor(d / 7));
}

export function pickWeightedChest(rng = Math.random, chests = CHESTS) {
  const list = Object.values(chests);
  const total = list.reduce((a, c) => a + c.earnWeight, 0);
  let r = rng() * total;
  for (const c of list) {
    r -= c.earnWeight;
    if (r <= 0) return c.id;
  }
  return list[list.length - 1].id;
}

export function rollChestReward(chestId, rng = Math.random, chests = CHESTS) {
  const chest = chests[chestId];
  if (!chest) throw new Error('unknown chest');
  assertOddsSum100(chest.odds, chestId);
  let r = rng() * 100;
  for (const o of chest.odds) {
    r -= o.pct;
    if (r <= 0) return { ...o, chestId };
  }
  return { ...chest.odds[chest.odds.length - 1], chestId };
}

export function chestUnlockMs(chestId, perks, chests = CHESTS) {
  const c = chests[chestId];
  const mult = perks?.chestTimeMult ?? 1;
  return Math.floor(c.unlockSec * 1000 * mult);
}

export function canEnqueueChest(state, perks) {
  const slots = perks?.chestSlots ?? 2;
  const active = (state.chests || []).filter((c) => !c.opened);
  return active.length < slots;
}

export function enqueueChest(state, chestId, now = Date.now(), perks = aggregatePerks(state.base?.levels)) {
  if (!canEnqueueChest(state, perks)) return { ok: false, reason: 'slots' };
  const unlockMs = chestUnlockMs(chestId, perks);
  const chest = {
    id: `${chestId}_${now}`,
    chestId,
    earnedAt: now,
    readyAt: now + unlockMs,
    opened: false,
  };
  return { ok: true, state: { ...state, chests: [...(state.chests || []), chest] } };
}

export function speedupChest(state, chestKey, now = Date.now()) {
  const chests = (state.chests || []).map((c) => ({ ...c }));
  const idx = chests.findIndex((c) => c.id === chestKey);
  if (idx < 0) return { ok: false, reason: 'missing' };
  const cost = gemsForReadyAt(chests[idx].readyAt, now);
  if ((state.gems || 0) < cost) return { ok: false, reason: 'gems', cost };
  chests[idx].readyAt = now;
  return { ok: true, cost, state: { ...state, gems: state.gems - cost, chests } };
}

export function openChestIfReady(state, chestKey, now = Date.now(), rng = Math.random) {
  const chests = (state.chests || []).map((c) => ({ ...c }));
  const idx = chests.findIndex((c) => c.id === chestKey);
  if (idx < 0) return { ok: false, reason: 'missing' };
  const c = chests[idx];
  if (c.opened) return { ok: false, reason: 'opened' };
  if (c.readyAt > now) return { ok: false, reason: 'locked', readyAt: c.readyAt };
  const reward = rollChestReward(c.chestId, rng);
  c.opened = true;
  c.openedAt = now;
  c.reward = reward;
  let next = { ...state, chests };
  if (reward.kind === 'scrap') next.scrap = (next.scrap || 0) + reward.n;
  if (reward.kind === 'gems') next.gems = (next.gems || 0) + reward.n;
  return { ok: true, reward, state: next };
}

export function formatOddsLine(odds) {
  return odds.map((o) => `${o.label} ${o.pct}%`).join(' · ');
}

export function migrateLegacySave(raw) {
  const s = { ...raw };
  if (s.scrap == null && s.shinies != null) s.scrap = s.shinies;
  if (s.gems == null) s.gems = 20;
  if (!s.base) {
    s.base = {
      levels: { recycler: 1, compactor: 1, neonSign: 1, stashVault: 1 },
      queue: [],
      builderSlots: BUILDERS.freeSlots,
    };
  }
  if (!s.chests) s.chests = [];
  if (!s.collection) s.collection = { skins: [], trails: [], bgs: [], outfits: [] };
  if (!s.notif) {
    s.notif = {
      permission: 'default',
      asked: false,
      enabled: { upgrade_done: true, chest_ready: true, daily_reward: true, streak_risk: true, new_season: true },
      quietHours: true,
      sentToday: 0,
      sentDate: '',
    };
  }
  if (!s.iap) s.iap = {};
  s.iap.starterBought = !!s.iap.starterBought;
  s.iap.removeAds = !!s.adsRemoved;
  if (!s.battlePass) s.battlePass = { season: SEASON_PASS.seasonId, xp: 0, claimedFree: [], claimedPremium: [] };
  if (s.battlePass.premium == null) s.battlePass.premium = !!s.premiumPass;
  if (s.streakFreeze == null) s.streakFreeze = 0;
  // Keep shinies mirrored for older UI paths during transition
  s.shinies = s.scrap;
  return s;
}

export function applyScrapGain(amount, perks, source) {
  let n = Math.max(0, amount | 0);
  if (source === 'recycle' && perks?.scrapRecycleBonus) n = Math.floor(n * (1 + perks.scrapRecycleBonus));
  if (source === 'clear' && perks?.scrapClearBonus) n = Math.floor(n * (1 + perks.scrapClearBonus));
  return n;
}

export function applyXpGain(amount, perks) {
  const n = Math.max(0, amount | 0);
  if (!perks?.xpBonus) return n;
  return Math.floor(n * (1 + perks.xpBonus));
}
