/**
 * Offline + trademark + store-readiness smoke checks for the web bundle.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const web = path.join(root, 'web');
const html = fs.readFileSync(path.join(web, 'index.html'), 'utf8');
const errors = [];

function fail(msg) {
  errors.push(msg);
}

if (/tetris/i.test(html)) fail('index.html must not contain the trademark "Tetris"');
if (!fs.existsSync(path.join(web, 'native.js'))) fail('web/native.js missing — run npm run build:native');
if (!fs.existsSync(path.join(web, 'privacy.html'))) fail('web/privacy.html missing');
if (!fs.existsSync(path.join(web, 'support.html'))) fail('web/support.html missing');
if (!fs.existsSync(path.join(web, 'icon-1024.png'))) fail('web/icon-1024.png missing — run npm run build:assets');

// No remote network deps in the game shell (fonts, CDNs, analytics)
const remote = html.match(/(?:src|href)\s*=\s*["']https?:\/\//gi) || [];
const allowedRemote = remote.filter((m) => !/privacy@|mailto:/i.test(m));
if (allowedRemote.length) fail(`External URL references in index.html: ${allowedRemote.join(', ')}`);

if (!/TrashNative/.test(html) && !/native\.js/.test(html)) {
  fail('index.html should load native.js bridge');
}
if (!/passBtn/.test(html) || !/disabled/.test(html)) {
  fail('Premium Pass button should be present and disabled');
}

if (errors.length) {
  console.error('validate-web FAILED:\n' + errors.map((e) => ' - ' + e).join('\n'));
  process.exit(1);
}
console.log('validate-web OK');
