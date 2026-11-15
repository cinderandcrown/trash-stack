/**
 * Offline + trademark + store-readiness + distinct-identity smoke checks.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const web = path.join(root, 'web');
const html = fs.readFileSync(path.join(web, 'index.html'), 'utf8');
const store = fs.existsSync(path.join(root, 'docs', 'STORE.md'))
  ? fs.readFileSync(path.join(root, 'docs', 'STORE.md'), 'utf8')
  : '';
const errors = [];

function fail(msg) {
  errors.push(msg);
}

if (/tetris/i.test(html)) fail('index.html must not contain the trademark "Tetris"');
if (/tetromino/i.test(html)) fail('index.html must not contain "tetromino"');
if (/tetris/i.test(store)) fail('docs/STORE.md must not contain the trademark "Tetris"');
if (/tetromino/i.test(store)) fail('docs/STORE.md must not contain "tetromino"');

if (!fs.existsSync(path.join(web, 'native.js'))) fail('web/native.js missing — run npm run build:native');
if (!fs.existsSync(path.join(web, 'privacy.html'))) fail('web/privacy.html missing');
if (!fs.existsSync(path.join(web, 'support.html'))) fail('web/support.html missing');
if (!fs.existsSync(path.join(web, 'icon-1024.png'))) fail('web/icon-1024.png missing — run npm run build:assets');

const remote = html.match(/(?:src|href)\s*=\s*["']https?:\/\//gi) || [];
const allowedRemote = remote.filter((m) => !/privacy@|mailto:/i.test(m));
if (allowedRemote.length) fail(`External URL references in index.html: ${allowedRemote.join(', ')}`);

if (!/TrashNative/.test(html) && !/native\.js/.test(html)) {
  fail('index.html should load native.js bridge');
}
if (!/passBtn/.test(html) || !/disabled/.test(html)) {
  fail('Premium Pass button should be present and disabled');
}
if (!/removeAdsBtn/.test(html)) {
  fail('Remove Ads stub button missing');
}
if (!/ad-config\.js/.test(html)) {
  fail('ad-config.js should be loaded');
}
if (!fs.existsSync(path.join(web, 'ad-config.js'))) fail('web/ad-config.js missing');
if ((html.match(/ACHIEVEMENTS/g) || []).length < 1) fail('Achievements system missing');

// Distinct identity: 8×15 compactor (not 10×20), junk set, signature systems
if (!/const COLS = 8/.test(html) || !/VIS = 15/.test(html)) {
  fail('Board must be 8 wide × 15 tall compactor bin');
}
if (/const COLS = 10/.test(html) || /VIS = 20/.test(html)) {
  fail('Legacy 10×20 well dimensions must be removed');
}
if (!/const JUNK =/.test(html)) fail('Junk piece catalog (JUNK) missing');
if (!/findRecycleGroups/.test(html)) fail('Recycle matching mechanic missing');
if (!/doMagnet/.test(html)) fail('Magnet power-up missing');
if (!/COMPACTOR|pressBar|juiceClear/.test(html)) fail('Compactor clear presentation missing');
if (!/Stash bin|stash/.test(html)) fail('Stash bin (not Hold) labeling missing');
if (!/mascot|Trash Panda/.test(html)) fail('Trash Panda mascot missing');
if (!/settingsOv|settingsBtn/.test(html)) fail('Settings screen missing');
if (!/runDemoSequence|shot==="demo"/.test(html)) fail('CI demo sequence missing');

const achIds = [...html.matchAll(/id:"([a-z0-9_]+)",\s*name:"/g)].map((m) => m[1]);
// ACHIEVEMENTS block ids only — filter by known prefix patterns is hard; count unique achievement-like
const achBlock = html.match(/const ACHIEVEMENTS = \[([\s\S]*?)\];/);
if (!achBlock) fail('ACHIEVEMENTS array missing');
else {
  const ids = [...achBlock[1].matchAll(/id:"([^"]+)"/g)].map((m) => m[1]);
  if (ids.length < 30) fail(`Need 30+ achievements, found ${ids.length}`);
}

if (errors.length) {
  console.error('validate-web FAILED:\n' + errors.map((e) => ' - ' + e).join('\n'));
  process.exit(1);
}
console.log('validate-web OK');
