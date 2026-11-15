/**
 * Inject gamification + ads JS into web/index.html (idempotent via META_JS_V2).
 */
import fs from 'node:fs';

const path = 'web/index.html';
let html = fs.readFileSync(path, 'utf8');
if (html.includes('META_JS_V2_BEGIN')) {
  console.log('META_JS_V2 already present');
  process.exit(0);
}

const DATA = `
/* META_JS_V2_BEGIN */
const TRAILS = [
  {id:"none", name:"No Trail", price:0, color:"transparent"},
  {id:"cyan", name:"Cyan Sparks", price:250, color:"#00f5ff"},
  {id:"mag", name:"Magenta Dust", price:350, color:"#ff2bd6"},
  {id:"gold", name:"Gold Embers", price:450, color:"#ffd166"},
  {id:"lime", name:"Lime Static", price:550, color:"#7dff6b"}
];
const ACHIEVEMENTS = [
  {id:"first_clear", name:"First Clear", desc:"Clear any line", goal:1, kind:"linesTotal", reward:20},
  {id:"lines_50", name:"Dock Sweeper", desc:"Clear 50 lines total", goal:50, kind:"linesTotal", reward:40},
  {id:"lines_200", name:"Night Janitor", desc:"Clear 200 lines total", goal:200, kind:"linesTotal", reward:80},
  {id:"lines_500", name:"City Recycler", desc:"Clear 500 lines total", goal:500, kind:"linesTotal", reward:150},
  {id:"score_1k", name:"Warm Up", desc:"Score 1,000 in a run", goal:1000, kind:"bestScore", reward:25},
  {id:"score_5k", name:"Neon Climber", desc:"Score 5,000 in a run", goal:5000, kind:"bestScore", reward:50},
  {id:"score_10k", name:"Skyline", desc:"Score 10,000 in a run", goal:10000, kind:"bestScore", reward:90},
  {id:"score_25k", name:"Overdrive", desc:"Score 25,000 in a run", goal:25000, kind:"bestScore", reward:160},
  {id:"combo_3", name:"Triple Threat", desc:"Hit a x3 combo", goal:3, kind:"bestCombo", reward:30},
  {id:"combo_5", name:"On Fire", desc:"Hit a x5 combo", goal:5, kind:"bestCombo", reward:60},
  {id:"combo_8", name:"Inferno", desc:"Hit a x8 combo", goal:8, kind:"bestCombo", reward:120},
  {id:"quad_1", name:"Full Sweep", desc:"Land a 4-line clear", goal:1, kind:"quads", reward:40},
  {id:"quad_10", name:"Sweep Artist", desc:"Land 10 four-line clears", goal:10, kind:"quads", reward:100},
  {id:"games_5", name:"Shift Starter", desc:"Play 5 runs", goal:5, kind:"games", reward:25},
  {id:"games_25", name:"Night Shift", desc:"Play 25 runs", goal:25, kind:"games", reward:70},
  {id:"games_100", name:"Dock Lifer", desc:"Play 100 runs", goal:100, kind:"games", reward:200},
  {id:"streak_3", name:"Three Nights", desc:"3-day login streak", goal:3, kind:"streak", reward:40},
  {id:"streak_7", name:"Week on the Docks", desc:"7-day login streak", goal:7, kind:"streak", reward:100},
  {id:"streak_14", name:"Fortnight Neon", desc:"14-day login streak", goal:14, kind:"streak", reward:180},
  {id:"level_5", name:"Rising Raccoon", desc:"Reach player level 5", goal:5, kind:"playerLevel", reward:50},
  {id:"level_10", name:"Mask Veteran", desc:"Reach player level 10", goal:10, kind:"playerLevel", reward:100},
  {id:"level_20", name:"Boss of Trash", desc:"Reach player level 20", goal:20, kind:"playerLevel", reward:220},
  {id:"shinies_500", name:"Shiny Pockets", desc:"Hold 500 Shinies at once", goal:500, kind:"shiniesHeld", reward:40},
  {id:"shinies_earned", name:"Hoarder", desc:"Earn 1,000 Shinies lifetime", goal:1000, kind:"shiniesEarned", reward:80},
  {id:"skins_3", name:"Wardrobe", desc:"Own 3 skins", goal:3, kind:"skinsOwned", reward:35},
  {id:"skins_all", name:"Full Closet", desc:"Own every skin", goal:7, kind:"skinsOwned", reward:150},
  {id:"bgs_3", name:"Scenic", desc:"Own 3 backgrounds", goal:3, kind:"bgsOwned", reward:35},
  {id:"hard_50", name:"Drop Machine", desc:"Hard-drop 50 times", goal:50, kind:"hardDrops", reward:40},
  {id:"spin_1", name:"Lucky Night", desc:"Spin the daily wheel", goal:1, kind:"spins", reward:20},
  {id:"spin_7", name:"Wheel Regular", desc:"Spin 7 times", goal:7, kind:"spins", reward:70},
  {id:"continue_1", name:"Second Chance", desc:"Revive once via rewarded ad", goal:1, kind:"continues", reward:30},
  {id:"pb_chase", name:"Chaser", desc:"Beat your personal best", goal:1, kind:"pbBeats", reward:45},
  {id:"week_clear", name:"Weekly Hero", desc:"Complete a weekly challenge", goal:1, kind:"weeklies", reward:60}
];
const WEEKLY_POOL = [
  {id:"w_lines100", name:"Clear 100 lines this week", goal:100, kind:"linesWeek", reward:120},
  {id:"w_score20k", name:"Best run score 20,000", goal:20000, kind:"scoreWeekBest", reward:140},
  {id:"w_quads5", name:"Land 5 four-line clears", goal:5, kind:"quadWeek", reward:110},
  {id:"w_games10", name:"Play 10 runs this week", goal:10, kind:"gamesWeek", reward:90},
  {id:"w_combo6", name:"Hit a x6 combo", goal:6, kind:"comboWeek", reward:130}
];
const BP_FREE = [
  {at:1, reward:{shinies:20}},
  {at:2, reward:{shinies:30}},
  {at:3, reward:{trail:"cyan"}},
  {at:4, reward:{shinies:40}},
  {at:5, reward:{shinies:50}},
  {at:6, reward:{bg:"rooftop"}},
  {at:7, reward:{shinies:60}},
  {at:8, reward:{shinies:80}},
  {at:9, reward:{skin:"glass"}},
  {at:10, reward:{shinies:120}}
];
const BP_PREMIUM = [
  {at:1, reward:{shinies:40}},
  {at:2, reward:{shinies:60}},
  {at:3, reward:{trail:"mag"}},
  {at:4, reward:{shinies:80}},
  {at:5, reward:{skin:"gold"}},
  {at:6, reward:{shinies:100}},
  {at:7, reward:{trail:"gold"}},
  {at:8, reward:{shinies:120}},
  {at:9, reward:{skin:"circuit"}},
  {at:10, reward:{shinies:200}}
];
const WHEEL_ODDS = WHEEL.map(w => ({ label:w.label, pct: Math.round(100/WHEEL.length) }));
/* META_JS_V2_END */
`;

// Insert after WHEEL constant
html = html.replace(
  /const WHEEL = \[[\s\S]*?\];\n/,
  (m) => m + '\n' + DATA + '\n'
);

// Expand defaultSave
html = html.replace(
  `function defaultSave(){
  return {
    highScore:0, shinies:50, xp:0, playerLevel:1,
    unlockedSkins:["neon"], unlockedBgs:["docks"],
    skin:"neon", bg:"docks", muted:false,
    dailyStreak:0, lastPlayDate:"", lastSpinDate:"",
    welcomed:false, sawHow:false,
    challenges:{date:"", items:[]},
    gamesPlayed:0, totalLines:0, dayLines:0, dayGames:0, dayDate:""
  };
}`,
  `function defaultSave(){
  return {
    highScore:0, shinies:50, xp:0, playerLevel:1,
    unlockedSkins:["neon"], unlockedBgs:["docks"], unlockedTrails:["none"],
    skin:"neon", bg:"docks", trail:"none", muted:false,
    dailyStreak:0, lastPlayDate:"", lastSpinDate:"", lastLoginClaim:"",
    loginHistory:[], welcomed:false, sawHow:false, adsRemoved:false, premiumPass:false,
    challenges:{date:"", items:[]},
    weekly:{week:"", items:[]},
    achievements:{},
    gamesPlayed:0, totalLines:0, dayLines:0, dayGames:0, dayDate:"",
    shiniesEarned:50, quads:0, hardDropTotal:0, bestCombo:0, spins:0, continues:0, pbBeats:0, weekliesDone:0,
    runShinies:0, localScores:[],
    battlePass:{ season:1, xp:0, claimedFree:[], claimedPremium:[] },
    // IAP stubs — TODO: StoreKit / Play Billing product IDs
    iap:{ removeAdsProductId:"", premiumPassProductId:"" }
  };
}`
);

// Expand rollDaily for weekly + ensure trails
html = html.replace(
  `function rollDaily(){
  const t = todayKey();
  if (save.dayDate !== t){ save.dayLines = 0; save.dayGames = 0; save.dayDate = t; }
  if (save.challenges.date !== t){
    const rng = hashStr(t + "hustle");
    const pool = CH_POOL.slice();
    const items = [];
    for (let i=0;i<3;i++){
      const idx = (rng + i*17) % pool.length;
      const ch = pool.splice(idx % pool.length, 1)[0];
      items.push({id:ch.id, name:ch.name, goal:ch.goal, kind:ch.kind, reward:ch.reward, progress:0, claimed:false});
    }
    save.challenges = {date:t, items};
  }
}`,
  `function weekKey(){
  const d=new Date();
  const onejan=new Date(d.getFullYear(),0,1);
  const week=Math.ceil((((d-onejan)/86400000)+onejan.getDay()+1)/7);
  return d.getFullYear()+"-W"+String(week).padStart(2,"0");
}
function rollDaily(){
  const t = todayKey();
  if (save.dayDate !== t){ save.dayLines = 0; save.dayGames = 0; save.dayDate = t; }
  if (!save.unlockedTrails) save.unlockedTrails=["none"];
  if (!save.achievements) save.achievements={};
  if (!save.localScores) save.localScores=[];
  if (!save.battlePass) save.battlePass={ season:1, xp:0, claimedFree:[], claimedPremium:[] };
  if (!save.loginHistory) save.loginHistory=[];
  if (save.challenges.date !== t){
    const rng = hashStr(t + "hustle");
    const pool = CH_POOL.slice();
    const items = [];
    for (let i=0;i<3;i++){
      const idx = (rng + i*17) % pool.length;
      const ch = pool.splice(idx % pool.length, 1)[0];
      items.push({id:ch.id, name:ch.name, goal:ch.goal, kind:ch.kind, reward:ch.reward, progress:0, claimed:false});
    }
    save.challenges = {date:t, items};
  }
  const wk = weekKey();
  if (!save.weekly || save.weekly.week !== wk){
    const rng = hashStr(wk + "week");
    const pool = WEEKLY_POOL.slice();
    const items=[];
    for (let i=0;i<2;i++){
      const idx = (rng + i*13) % pool.length;
      const ch = pool.splice(idx % pool.length, 1)[0];
      items.push({id:ch.id, name:ch.name, goal:ch.goal, kind:ch.kind, reward:ch.reward, progress:0, claimed:false});
    }
    save.weekly = {week:wk, items};
  }
}`
);

// Patch addShinies to track earned + achievements
html = html.replace(
  `function addShinies(n, why){
  if (!n) return;
  save.shinies += n;
  persist();
  syncMetaUI();
  SFX.coin();
}`,
  `function addShinies(n, why){
  if (!n) return;
  save.shinies += n;
  save.shiniesEarned = (save.shiniesEarned||0) + Math.max(0,n);
  if (why==="run") save.runShinies = (save.runShinies||0) + n;
  persist();
  syncMetaUI();
  SFX.coin();
  checkAchievements();
}`
);

// Add achievement + BP helpers after checkDailyStreak
html = html.replace(
  `function checkDailyStreak(){
  const t = todayKey();
  if (save.lastPlayDate === t) return;
  if (save.lastPlayDate === yesterdayKey()) save.dailyStreak += 1;
  else save.dailyStreak = 1;
  save.lastPlayDate = t;
  const bonus = Math.min(50, 5*save.dailyStreak);
  addShinies(bonus);
  persist();
  toast("Day "+save.dailyStreak+" streak  ·  +"+bonus+" Shinies");
}`,
  `function checkDailyStreak(){
  const t = todayKey();
  if (save.lastPlayDate === t) return;
  if (save.lastPlayDate === yesterdayKey()) save.dailyStreak += 1;
  else save.dailyStreak = 1;
  save.lastPlayDate = t;
  if (!save.loginHistory.includes(t)) save.loginHistory.push(t);
  while (save.loginHistory.length>42) save.loginHistory.shift();
  const bonus = Math.min(120, 5*save.dailyStreak + Math.floor(save.dailyStreak/7)*20);
  if (save.lastLoginClaim !== t){
    save.lastLoginClaim = t;
    addShinies(bonus);
    addBattlePassXP(8 + Math.min(20, save.dailyStreak));
    toast("Day "+save.dailyStreak+" streak  ·  +"+bonus+" Shinies");
  }
  persist();
  checkAchievements();
}

function achievementProgress(def){
  switch(def.kind){
    case "linesTotal": return save.totalLines||0;
    case "bestScore": return save.highScore||0;
    case "bestCombo": return save.bestCombo||0;
    case "quads": return save.quads||0;
    case "games": return save.gamesPlayed||0;
    case "streak": return save.dailyStreak||0;
    case "playerLevel": return save.playerLevel||1;
    case "shiniesHeld": return save.shinies||0;
    case "shiniesEarned": return save.shiniesEarned||0;
    case "skinsOwned": return (save.unlockedSkins||[]).length;
    case "bgsOwned": return (save.unlockedBgs||[]).length;
    case "hardDrops": return save.hardDropTotal||0;
    case "spins": return save.spins||0;
    case "continues": return save.continues||0;
    case "pbBeats": return save.pbBeats||0;
    case "weeklies": return save.weekliesDone||0;
    default: return 0;
  }
}
function checkAchievements(){
  if (!save.achievements) save.achievements={};
  let unlocked=0;
  for (const def of ACHIEVEMENTS){
    if (save.achievements[def.id]) continue;
    const p = achievementProgress(def);
    if (p >= def.goal){
      save.achievements[def.id] = { at: Date.now() };
      addShinies(def.reward);
      toast("Achievement: "+def.name+"  ·  +"+def.reward+" ✦");
      SFX.prize(); vibe(24);
      unlocked++;
    }
  }
  if (unlocked) persist();
}
function addBattlePassXP(n){
  if (!n) return;
  save.battlePass.xp = (save.battlePass.xp||0) + n;
  persist();
  claimBattlePassReady();
}
function bpTierUnlocked(){
  return Math.min(10, 1 + Math.floor((save.battlePass.xp||0)/100));
}
function grantBPReward(reward){
  if (reward.shinies) addShinies(reward.shinies);
  if (reward.skin && !save.unlockedSkins.includes(reward.skin)){ save.unlockedSkins.push(reward.skin); }
  if (reward.bg && !save.unlockedBgs.includes(reward.bg)){ save.unlockedBgs.push(reward.bg); }
  if (reward.trail && !save.unlockedTrails.includes(reward.trail)){ save.unlockedTrails.push(reward.trail); }
}
function claimBattlePassReady(){
  const tier = bpTierUnlocked();
  let got=false;
  for (const row of BP_FREE){
    if (row.at <= tier && !(save.battlePass.claimedFree||[]).includes(row.at)){
      save.battlePass.claimedFree.push(row.at);
      grantBPReward(row.reward);
      got=true;
    }
  }
  if (save.premiumPass){
    for (const row of BP_PREMIUM){
      if (row.at <= tier && !(save.battlePass.claimedPremium||[]).includes(row.at)){
        save.battlePass.claimedPremium.push(row.at);
        grantBPReward(row.reward);
        got=true;
      }
    }
  }
  if (got){ persist(); toast("Night Pass reward!"); }
}
function bumpWeekly(kind, amount){
  if (!save.weekly || !save.weekly.items) return;
  for (const ch of save.weekly.items){
    if (ch.claimed) continue;
    if (ch.kind==="linesWeek" && kind==="lines") ch.progress = Math.min(ch.goal, ch.progress+amount);
    if (ch.kind==="gamesWeek" && kind==="games") ch.progress = Math.min(ch.goal, ch.progress+amount);
    if (ch.kind==="quadWeek" && kind==="quad") ch.progress = Math.min(ch.goal, ch.progress+amount);
    if (ch.kind==="scoreWeekBest" && kind==="score") ch.progress = Math.max(ch.progress, amount);
    if (ch.kind==="comboWeek" && kind==="combo") ch.progress = Math.max(ch.progress, amount);
    if (ch.progress>=ch.goal && !ch.claimed){
      ch.claimed=true; ch.progress=ch.goal;
      addShinies(ch.reward);
      save.weekliesDone = (save.weekliesDone||0)+1;
      toast("Weekly done! +"+ch.reward+" Shinies");
      checkAchievements();
    }
  }
  persist();
}`
);

// Expand resetRun for continue state
html = html.replace(
  `function resetRun(){
  board = emptyBoard();
  bag=[]; queue=[];
  hold=null; holdUsed=false;
  score=0; lines=0; level=1; combo=0; b2b=false;
  dropping=false; paused=false; over=false; started=true;
  gravityAcc=0; locking=false; lockT=0; clearT=0; clearing=null;
  hardDrops=0; particles.length=0; shake=0; flashA=0;
  keys={}; dasDir=0;
  nextPiece();
  syncGameUI();
}`,
  `let continuedThisRun=false;
let pendingGameOver=false;
let lastRunShinies=0;
function resetRun(){
  board = emptyBoard();
  bag=[]; queue=[];
  hold=null; holdUsed=false;
  score=0; lines=0; level=1; combo=0; b2b=false;
  dropping=false; paused=false; over=false; started=true;
  gravityAcc=0; locking=false; lockT=0; clearT=0; clearing=null;
  hardDrops=0; particles.length=0; shake=0; flashA=0;
  keys={}; dasDir=0;
  continuedThisRun=false; pendingGameOver=false;
  save.runShinies=0; lastRunShinies=0;
  nextPiece();
  syncGameUI();
  const bridge = TN();
  if (bridge && bridge.noteRunStarted) bridge.noteRunStarted();
}`
);

// Patch juiceClear for bestCombo, quads, BP, weekly
html = html.replace(
  `  bumpChallenge("lines", n);
  bumpChallenge("score", score);
  bumpChallenge("combo", combo);
  if (n===4) bumpChallenge("quad", 1);`,
  `  bumpChallenge("lines", n);
  bumpChallenge("score", score);
  bumpChallenge("combo", combo);
  if (n===4){ bumpChallenge("quad", 1); save.quads=(save.quads||0)+1; bumpWeekly("quad",1); }
  bumpWeekly("lines", n);
  bumpWeekly("score", score);
  bumpWeekly("combo", combo);
  if (combo > (save.bestCombo||0)) save.bestCombo = combo;
  addBattlePassXP(n*2 + Math.min(8, combo));
  checkAchievements();`
);

// Patch hard drop tracking - find hardDrop function
// Will search and patch

fs.writeFileSync(path, html);
console.log('Injected META_JS_V2 data + progression helpers');
