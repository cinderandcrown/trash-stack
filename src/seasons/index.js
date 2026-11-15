/**
 * Season registry — add a file + import here to ship a new season (no game-code edits).
 */
import { SEASON_1_NEON_DUMPSTER } from './season-1-neon-dumpster.js';

export const SEASONS = {
  [SEASON_1_NEON_DUMPSTER.id]: SEASON_1_NEON_DUMPSTER,
  [SEASON_1_NEON_DUMPSTER.slug]: SEASON_1_NEON_DUMPSTER,
};

export const ACTIVE_SEASON_ID = 1;

export function getSeason(id = ACTIVE_SEASON_ID) {
  return SEASONS[id] || SEASON_1_NEON_DUMPSTER;
}

export function listSeasons() {
  return [SEASON_1_NEON_DUMPSTER];
}

export { SEASON_1_NEON_DUMPSTER };
