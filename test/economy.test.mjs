import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  validateChestTables,
  assertOddsSum100,
  upgradeCost,
  aggregatePerks,
  gemsForSpeedup,
  gemsForReadyAt,
  canStartUpgrade,
  applyStartUpgrade,
  completeReadyUpgrades,
  speedupQueueItem,
  seasonTierUnlocked,
  loginStreakScrap,
  pickWeightedChest,
  rollChestReward,
  enqueueChest,
  speedupChest,
  openChestIfReady,
  migrateLegacySave,
  applyScrapGain,
  applyXpGain,
  formatOddsLine,
} from '../src/economy-math.js';
import { CHESTS, SEASON_PASS, BUILDINGS, SPEEDUP, GEM_PACKS, STARTER_PACK } from '../src/economy-config.js';

describe('compliance / odds', () => {
  it('all chest odds sum to 100', () => {
    assert.equal(validateChestTables(), true);
  });
  it('rejects bad odds', () => {
    assert.throws(() => assertOddsSum100([{ pct: 50 }, { pct: 40 }]));
  });
  it('formatOddsLine includes percents', () => {
    const line = formatOddsLine(CHESTS.dock_crate.odds);
    assert.match(line, /%/);
    assert.match(line, /Scrap/);
  });
  it('gem packs include 0.99–49.99 tiers + starter', () => {
    assert.equal(GEM_PACKS[0].priceUsd, 0.99);
    assert.equal(GEM_PACKS[GEM_PACKS.length - 1].priceUsd, 49.99);
    assert.equal(STARTER_PACK.oneTime, true);
  });
});

describe('buildings', () => {
  it('upgradeCost returns scrap + time', () => {
    const c = upgradeCost('recycler', 1);
    assert.equal(c.toLevel, 2);
    assert.ok(c.scrap > 0);
    assert.ok(c.sec > 0);
  });
  it('max level returns null', () => {
    assert.equal(upgradeCost('recycler', BUILDINGS.recycler.maxLevel), null);
  });
  it('aggregatePerks stacks bonuses', () => {
    const p = aggregatePerks({ recycler: 3, compactor: 2, neonSign: 2, stashVault: 2 });
    assert.ok(p.scrapRecycleBonus >= 0.1);
    assert.ok(p.chestSlots >= 3);
  });
});

describe('speedup math', () => {
  it('gemsForSpeedup uses secPerGem', () => {
    assert.equal(gemsForSpeedup(0), 0);
    assert.equal(gemsForSpeedup(1000), 1);
    assert.equal(gemsForSpeedup(SPEEDUP.secPerGem * 1000), 1);
    assert.equal(gemsForSpeedup(SPEEDUP.secPerGem * 1000 + 1), 2);
  });
  it('gemsForReadyAt matches remaining', () => {
    const now = 1_000_000;
    assert.equal(gemsForReadyAt(now + 125_000, now), Math.ceil(125 / SPEEDUP.secPerGem));
  });
});

describe('upgrade queue', () => {
  function baseState(over = {}) {
    return migrateLegacySave({
      scrap: 5000,
      gems: 100,
      base: {
        levels: { recycler: 1, compactor: 1, neonSign: 1, stashVault: 1 },
        queue: [],
        builderSlots: 2,
      },
      ...over,
    });
  }
  it('starts upgrade and spends scrap', () => {
    const s0 = baseState();
    const { ok, state } = applyStartUpgrade(s0, 'recycler', 1000);
    assert.equal(ok, true);
    assert.ok(state.scrap < s0.scrap);
    assert.equal(state.base.queue.length, 1);
  });
  it('blocks when no builders', () => {
    const s0 = baseState({
      base: {
        levels: { recycler: 1, compactor: 1, neonSign: 1, stashVault: 1 },
        queue: [
          { buildingId: 'recycler', from: 1, to: 2, startedAt: 0, readyAt: 9e12 },
          { buildingId: 'compactor', from: 1, to: 2, startedAt: 0, readyAt: 9e12 },
        ],
        builderSlots: 2,
      },
    });
    assert.equal(canStartUpgrade(s0, 'neonSign').ok, false);
    assert.equal(canStartUpgrade(s0, 'neonSign').reason, 'builders');
  });
  it('completes when ready', () => {
    const s0 = baseState({
      base: {
        levels: { recycler: 1, compactor: 1, neonSign: 1, stashVault: 1 },
        queue: [{ buildingId: 'recycler', from: 1, to: 2, startedAt: 0, readyAt: 50 }],
        builderSlots: 2,
      },
    });
    const { state, completed } = completeReadyUpgrades(s0, 100);
    assert.equal(completed.length, 1);
    assert.equal(state.base.levels.recycler, 2);
  });
  it('speedup spends gems and finishes', () => {
    const s0 = baseState({
      gems: 50,
      base: {
        levels: { recycler: 1, compactor: 1, neonSign: 1, stashVault: 1 },
        queue: [{ buildingId: 'recycler', from: 1, to: 2, startedAt: 0, readyAt: 1_000_000 + 600_000 }],
        builderSlots: 2,
      },
    });
    const res = speedupQueueItem(s0, 0, 1_000_000);
    assert.equal(res.ok, true);
    assert.ok(res.cost >= 1);
    assert.equal(res.state.base.levels.recycler, 2);
  });
});

describe('season + login', () => {
  it('season has 30 tiers', () => {
    assert.equal(SEASON_PASS.tiers, 30);
    assert.equal(SEASON_PASS.free.length, 30);
    assert.equal(SEASON_PASS.premium.length, 30);
  });
  it('seasonTierUnlocked clamps', () => {
    assert.equal(seasonTierUnlocked(0), 0);
    assert.equal(seasonTierUnlocked(100), 1);
    assert.equal(seasonTierUnlocked(99999), 30);
  });
  it('login streak escalates and caps', () => {
    assert.equal(loginStreakScrap(1), 5);
    assert.ok(loginStreakScrap(14) > loginStreakScrap(7));
    assert.equal(loginStreakScrap(999), 120);
  });
});

describe('chests', () => {
  it('weighted pick is deterministic with stub rng', () => {
    assert.equal(pickWeightedChest(() => 0), 'dock_crate');
  });
  it('roll respects odds table', () => {
    const r = rollChestReward('dock_crate', () => 0);
    assert.equal(r.kind, 'scrap');
  });
  it('enqueue + open flow', () => {
    let s = migrateLegacySave({ scrap: 0, gems: 100, base: { levels: { stashVault: 1 }, queue: [], builderSlots: 2 } });
    const en = enqueueChest(s, 'dock_crate', 1000, aggregatePerks(s.base.levels));
    assert.equal(en.ok, true);
    s = en.state;
    const locked = openChestIfReady(s, s.chests[0].id, 1001);
    assert.equal(locked.ok, false);
    const sped = speedupChest(s, s.chests[0].id, 1001);
    assert.equal(sped.ok, true);
    s = sped.state;
    const opened = openChestIfReady(s, s.chests[0].id, 1001, () => 0);
    assert.equal(opened.ok, true);
    assert.ok(opened.state.scrap > 0);
  });
});

describe('migration + perks', () => {
  it('migrates shinies to scrap', () => {
    const s = migrateLegacySave({ shinies: 77 });
    assert.equal(s.scrap, 77);
    assert.ok(s.base.levels.recycler);
  });
  it('applyScrapGain / applyXpGain', () => {
    const perks = { scrapRecycleBonus: 0.5, scrapClearBonus: 0.5, xpBonus: 0.1 };
    assert.equal(applyScrapGain(100, perks, 'recycle'), 150);
    assert.equal(applyScrapGain(100, perks, 'clear'), 150);
    assert.equal(applyXpGain(100, perks), 110);
  });
});
