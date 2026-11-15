/**
 * One-shot injector: expands Trash Stack index.html with ads + gamification.
 * Idempotent via META_V2 markers.
 */
import fs from 'node:fs';

const path = 'web/index.html';
let html = fs.readFileSync(path, 'utf8');
if (html.includes('META_V2_BEGIN')) {
  console.log('META_V2 already present');
  process.exit(0);
}

// 1) Load ad-config before native bridge
html = html.replace(
  '<script type="module" src="native.js"></script>',
  `<script src="ad-config.js"></script>\n<script type="module" src="native.js"></script>`
);

// 2) Extra CSS
const css = `
/* META_V2_BEGIN */
.btn.tiny{padding:8px 10px;font-size:11px;border-radius:10px}
.panel-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;width:min(360px,92%);margin:8px auto 0}
.ach-list,.lb-list,.bp-list,.cal-grid{max-height:42vh;overflow:auto;margin:8px 0;text-align:left}
.ach-row,.lb-row,.bp-row{display:flex;gap:8px;align-items:center;padding:8px;border-radius:10px;background:#0e1220;border:1px solid rgba(255,255,255,.08);margin:6px 0;font-size:12px}
.ach-row.on{border-color:rgba(125,255,107,.45)}
.ach-ico{width:28px;height:28px;border-radius:8px;display:grid;place-items:center;background:#16182a;flex:0 0 auto}
.odds{font-size:11px;color:var(--dim);text-align:left;margin:8px 0;line-height:1.45}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:4px}
.cal-day{aspect-ratio:1;border-radius:8px;background:#12162a;border:1px solid rgba(255,255,255,.08);display:grid;place-items:center;font-size:10px;color:var(--dim)}
.cal-day.on{background:linear-gradient(180deg,#1a3a40,#102028);border-color:var(--cyan);color:var(--cyan);font-weight:800}
.cal-day.today{box-shadow:0 0 0 1px var(--gold)}
.bp-track{height:10px;background:#1a1d30;border-radius:99px;overflow:hidden;border:1px solid rgba(255,255,255,.08);margin:6px 0 10px}
.bp-fill{height:100%;background:linear-gradient(90deg,var(--cyan),var(--mag))}
.trail-dot{width:10px;height:10px;border-radius:50%;display:inline-block;margin-right:4px}
#continueOv .card{border-color:rgba(255,43,214,.45)}
/* META_V2_END */
`;
html = html.replace('</style>', css + '\n</style>');

// 3) Title screen buttons — insert meta panel before passBtn
const metaBtns = `
    <div class="panel-grid">
      <button class="btn ghost small" id="achBtn" type="button">Achievements</button>
      <button class="btn ghost small" id="lbBtn" type="button">Records</button>
      <button class="btn ghost small" id="bpBtn" type="button">Night Pass</button>
      <button class="btn ghost small" id="calBtn" type="button">Streak</button>
    </div>
`;
html = html.replace(
  '<button class="btn gold wide" id="passBtn"',
  metaBtns + '\n    <button class="btn mag wide" id="removeAdsBtn" type="button" disabled aria-disabled="true" style="margin-top:10px;opacity:.55;font-size:13px;padding:12px">Remove Ads (coming soon)</button>\n    <button class="btn gold wide" id="passBtn"'
);

// Update premium note
html = html.replace(
  /<p id="premiumNote">[\s\S]*?<\/p>/,
  `<p id="premiumNote">Free to play with optional rewarded ads. Remove Ads &amp; Premium Pass are coming — no real-money gambling.</p>`
);

// How-to update
html = html.replace(
  '<li>Earn Shinies, level up, and unlock looks. No real-money shop.</li>',
  '<li>Earn Shinies (soft currency), level up, unlock looks, chase achievements.</li>\n    <li>Optional rewarded ads for continue, double Shinies, or an extra daily spin. Odds shown for random rewards.</li>'
);

// 4) Overlays before #flash
const overlays = `
<div id="continueOv" class="overlay hidden"><div class="card">
  <h2>ONE MORE?</h2>
  <p>Watch a short rewarded ad to revive once this run.</p>
  <button class="btn wide pulse" id="continueAdBtn" type="button">Revive (ad)</button>
  <button class="btn ghost wide" id="continueSkipBtn" type="button" style="margin-top:10px">Stack out</button>
</div></div>

<div id="doubleOv" class="overlay hidden"><div class="card">
  <h2>DOUBLE SHINIES?</h2>
  <p id="doubleHint">Watch a rewarded ad to double Shinies earned this run.</p>
  <button class="btn wide gold" id="doubleAdBtn" type="button" style="box-shadow:0 0 0 1px rgba(255,255,255,.25) inset,0 8px 0 #9a7010">Double (ad)</button>
  <button class="btn ghost wide" id="doubleSkipBtn" type="button" style="margin-top:10px">Keep as-is</button>
</div></div>

<div id="achOv" class="overlay hidden"><div class="card">
  <h2>ACHIEVEMENTS</h2>
  <p id="achProgress">0 / 0</p>
  <div id="achList" class="ach-list"></div>
  <button class="btn ghost wide" id="achClose" type="button">Close</button>
</div></div>

<div id="lbOv" class="overlay hidden"><div class="card">
  <h2>LOCAL RECORDS</h2>
  <p>Personal best chase — saved on this device only.</p>
  <div id="lbList" class="lb-list"></div>
  <button class="btn ghost wide" id="lbClose" type="button">Close</button>
</div></div>

<div id="bpOv" class="overlay hidden"><div class="card">
  <h2>NIGHT PASS</h2>
  <p>Season track. Free lane active. Premium lane is a stub.</p>
  <div class="bp-track"><div class="bp-fill" id="bpFill"></div></div>
  <div id="bpList" class="bp-list"></div>
  <button class="btn gold wide" id="bpPremiumBtn" type="button" disabled style="opacity:.55">Premium Pass (coming soon)</button>
  <button class="btn ghost wide" id="bpClose" type="button" style="margin-top:10px">Close</button>
</div></div>

<div id="calOv" class="overlay hidden"><div class="card">
  <h2>STREAK CALENDAR</h2>
  <p id="calHint">Login streak rewards escalate each day.</p>
  <div id="calGrid" class="cal-grid"></div>
  <div class="odds" id="calOdds"></div>
  <button class="btn ghost wide" id="calClose" type="button">Close</button>
</div></div>
`;
html = html.replace('<div id="flash"></div>', overlays + '\n<div id="flash"></div>');

// 5) Spin odds UI
html = html.replace(
  '<p id="spinHint">Free once a day. Cosmetics and Shinies only.</p>',
  `<p id="spinHint">Free once a day. Cosmetics and Shinies only.</p>
  <div class="odds" id="spinOdds"></div>
  <button class="btn mag small smag" id="spinAdBtn" type="button" style="width:100%;margin:6px 0;display:none">Extra spin (rewarded ad)</button>`
);

fs.writeFileSync(path, html);
console.log('Injected META_V2 HTML/CSS shells');
