/**
 * Browser bundle entry — exposes TrashEconomyConfig + TrashEconomy on window.
 */
import * as Config from './economy-config.js';
import * as MathApi from './economy-math.js';

Config.attachEconomyGlobal(globalThis);
globalThis.TrashEconomy = MathApi;
