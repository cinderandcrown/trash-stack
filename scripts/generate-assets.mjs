/**
 * Build App Store / Play icon (1024 opaque) and splash art from web/icon-512.png.
 * Neon Trash Stack look: deep night dock bg + scaled raccoon mark.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');

// Prefer sharp (pulled in by @capacitor/assets); fall back to pure Pillow via child if needed.
let sharp;
try {
  sharp = (await import('sharp')).default;
} catch {
  console.error('sharp is required for asset generation');
  process.exit(1);
}

const srcIcon = path.join(root, 'web', 'icon-512.png');
const resDir = path.join(root, 'resources');
const webDir = path.join(root, 'web');
fs.mkdirSync(resDir, { recursive: true });

const BG = { r: 7, g: 7, b: 15, alpha: 1 };

async function opaqueIcon1024() {
  const mark = await sharp(srcIcon)
    .resize(720, 720, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();

  const dumpsterChrome = Buffer.from(`
    <svg width="1024" height="1024" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="bin" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#1a2438"/>
          <stop offset="100%" stop-color="#07070f"/>
        </linearGradient>
        <linearGradient id="rim" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stop-color="#ff2bd6"/>
          <stop offset="50%" stop-color="#00f5ff"/>
          <stop offset="100%" stop-color="#ff2bd6"/>
        </linearGradient>
      </defs>
      <rect width="1024" height="1024" fill="#07070f"/>
      <rect x="120" y="180" width="784" height="720" rx="48" fill="url(#bin)" stroke="url(#rim)" stroke-width="18"/>
      <rect x="200" y="150" width="624" height="48" rx="12" fill="#4a5568" stroke="#00f5ff" stroke-width="4"/>
      <rect x="160" y="220" width="28" height="640" rx="8" fill="#00c8b4" opacity="0.55"/>
      <rect x="836" y="220" width="28" height="640" rx="8" fill="#ff2bd6" opacity="0.45"/>
      <text x="512" y="960" text-anchor="middle" font-family="Arial Black, Helvetica, sans-serif"
        font-size="54" font-weight="800" letter-spacing="6" fill="#00f5ff">TRASH STACK</text>
    </svg>`);

  const out = path.join(resDir, 'icon.png');
  await sharp(dumpsterChrome)
    .composite([{ input: mark, top: 210, left: 152 }])
    .flatten({ background: BG })
    .removeAlpha()
    .png()
    .toFile(out);

  // Verify no alpha
  const meta = await sharp(out).metadata();
  if (meta.hasAlpha) {
    await sharp(out).removeAlpha().png().toFile(out);
  }
  // Copy for web / marketing
  fs.copyFileSync(out, path.join(webDir, 'icon-1024.png'));
  console.log('Wrote', out, 'channels=', (await sharp(out).metadata()).channels);
}

async function splash2732() {
  // Universal splash canvas (iOS legacy + Android adaptive source)
  const W = 2732;
  const H = 2732;
  const mark = await sharp(srcIcon)
    .resize(920, 920, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();

  // Soft neon glow rings behind the mark (SVG overlay)
  const glow = Buffer.from(`
    <svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <radialGradient id="g1" cx="50%" cy="46%" r="42%">
          <stop offset="0%" stop-color="#00f5ff" stop-opacity="0.28"/>
          <stop offset="45%" stop-color="#ff2bd6" stop-opacity="0.14"/>
          <stop offset="100%" stop-color="#07070f" stop-opacity="0"/>
        </radialGradient>
        <radialGradient id="g2" cx="50%" cy="70%" r="50%">
          <stop offset="0%" stop-color="#ffd166" stop-opacity="0.10"/>
          <stop offset="100%" stop-color="#07070f" stop-opacity="0"/>
        </radialGradient>
      </defs>
      <rect width="100%" height="100%" fill="#07070f"/>
      <rect width="100%" height="100%" fill="url(#g1)"/>
      <rect width="100%" height="100%" fill="url(#g2)"/>
      <text x="50%" y="72%" text-anchor="middle" font-family="Arial Black, Helvetica, sans-serif"
        font-size="96" font-weight="800" letter-spacing="14"
        fill="#00f5ff" opacity="0.95">TRASH STACK</text>
      <text x="50%" y="76.5%" text-anchor="middle" font-family="Helvetica, Arial, sans-serif"
        font-size="36" letter-spacing="10"         fill="#8b93b3">NEON JUNK · COMPACTOR SHIFT</text>
    </svg>
  `);

  const out = path.join(resDir, 'splash.png');
  await sharp(glow)
    .composite([{ input: mark, top: Math.round(H * 0.28), left: Math.round((W - 920) / 2) }])
    .png()
    .toFile(out);

  // Portrait phone splash (1284x2778-ish marketing)
  const phoneW = 1284;
  const phoneH = 2778;
  const phoneMark = await sharp(srcIcon)
    .resize(640, 640, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();
  const phoneGlow = Buffer.from(`
    <svg width="${phoneW}" height="${phoneH}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <radialGradient id="g1" cx="50%" cy="40%" r="48%">
          <stop offset="0%" stop-color="#00f5ff" stop-opacity="0.30"/>
          <stop offset="50%" stop-color="#ff2bd6" stop-opacity="0.14"/>
          <stop offset="100%" stop-color="#07070f" stop-opacity="0"/>
        </radialGradient>
      </defs>
      <rect width="100%" height="100%" fill="#07070f"/>
      <rect width="100%" height="100%" fill="url(#g1)"/>
      <text x="50%" y="58%" text-anchor="middle" font-family="Arial Black, Helvetica, sans-serif"
        font-size="72" font-weight="800" letter-spacing="10"
        fill="#00f5ff">TRASH STACK</text>
      <text x="50%" y="62%" text-anchor="middle" font-family="Helvetica, Arial, sans-serif"
        font-size="28" letter-spacing="8" fill="#8b93b3">NEON JUNK · COMPACTOR SHIFT</text>
    </svg>
  `);
  await sharp(phoneGlow)
    .composite([{ input: phoneMark, top: Math.round(phoneH * 0.28), left: Math.round((phoneW - 640) / 2) }])
    .png()
    .toFile(path.join(resDir, 'splash-portrait.png'));

  console.log('Wrote splash assets');
}

await opaqueIcon1024();
await splash2732();

// Also emit a simple logo foreground for Android adaptive icon
await sharp(srcIcon)
  .resize(768, 768, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
  .png()
  .toFile(path.join(resDir, 'icon-foreground.png'));

console.log('Asset generation complete');
