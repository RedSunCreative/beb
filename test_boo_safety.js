#!/usr/bin/env node
// Boo safety contract — replays the real failures of 2026-11-04 against the REAL beb.html code
// (functions extracted verbatim), with Supabase, the Claude API and the DOM simulated.
//   node test_boo_safety.js [path/to/beb.html]
// Prints PASS:/FAIL: lines. Exit code = number of failures.
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const BEB = path.resolve(process.argv[2] || path.join(__dirname, 'beb.html'));
const src = fs.readFileSync(BEB, 'utf8');
let fails = 0;
const ok = (c, m) => { console.log((c ? 'PASS: ' : 'FAIL: ') + m); if (!c) fails++; };

function extract(name) {
  for (const pre of ['async function ', 'function ']) {
    const i = src.indexOf(pre + name + '(');
    if (i < 0) continue;
    // skip matches that are part of a longer identifier
    if (i > 0 && /[\w$]/.test(src[i - 1])) continue;
    // Top-level BEB functions close with "}" at column 0 — robust to braces inside strings/regexes.
    const end = src.indexOf('\n}\n', i);
    if (end > i) return src.slice(i, end + 2);
  }
  throw new Error('MISSING function ' + name);
}
const FNS = ['isBooCrew', 'listAllRows', 'blankShowData', 'episodeNumberChange', 'saveWouldOverwrite', 'rowForEpisode', 'saveState',
  'loadState', 'listEpisodes', 'applyBooUpdates', 'openEpisodeNumber', 'claimsChange', 'updatedKinds',
  'parseBooReplyText', 'processUserInput', 'parseEpDate', 'normalizeEpDate', 'formatDateLong', 'handleNewEpisode'];
let code;
try { code = FNS.map(extract).join('\n\n'); }
catch (e) { ok(false, 'extract BEB functions: ' + e.message); process.exit(1); }

// ── one fresh simulated world per scenario ─────────────────────────────────────────────
function world({ db, loaded, row, replies }) {
  const el = () => new Proxy({ classList: { add() {}, remove() {} }, style: {}, value: '', disabled: false }, {
    get: (t, k) => (k in t ? t[k] : (typeof k === 'string' ? '' : undefined)), set: (t, k, v) => { t[k] = v; return true; } });
  const W = {
    DB: JSON.parse(JSON.stringify(db)), writes: [], booMsgs: [], badges: [], calls: [], replies: replies.slice(),
  };
  const ctx = {
    console: { error() {}, log() {} }, setTimeout: (f) => 0, clearTimeout() {}, JSON, Math, Date, String, Number,
    Array, Object, RegExp, parseInt, parseFloat, Promise,
    localStorage: { setItem() {}, getItem() { return null; } },
    document: { getElementById: el, querySelector: el, createElement: el },
    CLIENT_CONFIG: { defaultEpLen: 90, defaultPin: '5000' }, GLOBAL_MEM_ROW: 9000,
    isThinking: false, silenceTimer: 0, pendingTranscript: '',
    showData: JSON.parse(JSON.stringify(loaded)), conversationHistory: [],
    currentEpRow: row, currentRowEpNum: String(loaded.epNum || ''),
    addUserMessage() {}, setMicStatus() {}, showThinking() {}, hideThinking() {}, updateAllDisplays() {},
    updateEpSwitchBtn() {}, speakBoo: async () => {}, runPreflight() {}, setSavedTime() {},
    setSaveBadge: (t) => W.badges.push(t), addBooMessage: (h) => W.booMsgs.push(String(h)),
    buildHistoryEntry: (r) => ({ role: 'assistant', content: JSON.stringify(r) }),
    normalizeGuest: (g) => g, recomputeStructuralFields: (c) => c,
    esc: (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'),
    callClaude: async (msg) => { W.calls.push(msg); const r = W.replies.shift(); return r === undefined ? { speech: '', display: '', updates: {} } : r; },
    sb: {
      rpc: async (fn, a) => {
        W.writes.push({ id: a.p_id, epNum: a.p_data.epNum });
        W.DB[a.p_id] = { ...(W.DB[a.p_id] || {}), ...JSON.parse(JSON.stringify(a.p_data)) };
        return { error: null };
      },
      from: () => {
        const q = { _id: null, _gt: -Infinity, _lt: Infinity };
        const api = {
          select() { return api; }, eq(_, v) { q._id = v; return api; }, gt(_, v) { q._gt = v; return api; },
          lt(_, v) { q._lt = v; return api; }, order() { return api; },
          single: async () => ({ data: W.DB[q._id] ? { id: q._id, data: W.DB[q._id], history: [] } : null }),
          maybeSingle: async () => ({ data: null }),
          then(res) { res({ data: Object.keys(W.DB).map(Number).filter(id => id > q._gt && id < q._lt).map(id => ({ id, data: W.DB[id] })) }); },
        };
        return api;
      },
    },
  };
  ctx.setCues = (c) => { ctx.showData.cues = c; };
  vm.createContext(ctx);
  vm.runInContext(code + '\nthis.__fns = { isBooCrew, saveState, applyBooUpdates, processUserInput, parseBooReplyText, claimsChange, episodeNumberChange, saveWouldOverwrite, rowForEpisode, parseEpDate, normalizeEpDate, formatDateLong };', ctx);
  W.ctx = ctx; W.fn = ctx.__fns;
  W.settle = () => new Promise(r => setImmediate(r));
  return W;
}

const E11_CUES = [{ scene: 'COUNTDOWN — Pre-Show', dur: 20, prelive: true }, { scene: 'POD INTERVIEW — Clifton Pappas', dur: 15 }];
const E11 = { epNum: '11', epTitle: 'Little Big Perspectives', epDate: '9-13-2026', cues: E11_CUES, guests: [{ name: 'Clifton Pappas' }], crew: [{ name: 'Sam Wofford' }] };
const BASE_DB = { 10: { epNum: '10', epTitle: 'Little Big Community Chill' }, 11: E11, 98: { meta: 'Boo Producer season row' }, 99: { epNum: '9', epTitle: 'Little Big Resilience' } };
const E12_CUES = [{ scene: 'COUNTDOWN — Pre-Show', dur: 20, prelive: true }, { scene: 'ROUND 1 — Getting to know you', dur: 12 }];

(async () => {
  // 1. Tonight's overwrite: "Let's start E12" with E11 loaded.
  {
    const W = world({ db: BASE_DB, loaded: E11, row: 11, replies: [
      { speech: 'Solid title.', display: 'Solid title.', updates: { epNum: '12', epTitle: 'Little Big Gratitude', cues: E12_CUES } }] });
    await W.fn.processUserInput("Let's start E12: Little Big Gratitude"); await W.settle();
    ok(W.DB[11].epNum === '11' && W.DB[11].epTitle === 'Little Big Perspectives' && W.DB[11].cues.length === 2 && W.DB[11].cues[1].scene.includes('Clifton'),
      'overwrite: "start E12" with E11 open leaves E11\'s row exactly as it was');
    ok(!W.writes.some(w => w.id === 11 && w.epNum !== '11'), 'overwrite: nothing carrying another episode number is ever written to row 11');
    ok(W.DB[12] && W.DB[12].epNum === '12' && W.DB[12].epTitle === 'Little Big Gratitude' && W.DB[12].cues[1].scene.startsWith('ROUND 1'),
      'overwrite: E12 lands in its own row 12 with Boo\'s new scenes');
    ok(W.ctx.currentEpRow === 12 && W.ctx.currentRowEpNum === '12', 'overwrite: BEB is now editing E12 (row 12)');
    ok(!(W.DB[12].guests || []).some(g => g.name === 'Clifton Pappas'), 'overwrite: E12 does not inherit E11\'s guest roster by accident');
    ok(W.booMsgs.some(m => /Started E12 as its own episode\. E11 is untouched/.test(m)), 'overwrite: Mark is told E12 started separately and E11 is untouched');
  }
  // 2. Same, but E12 already exists → switch to it, don't create a duplicate, don't touch E11.
  {
    const W = world({ db: { ...BASE_DB, 12: { epNum: '12', epTitle: 'Little Big Gratitude', cues: E12_CUES, guests: [{ name: 'Jimmy George' }] } }, loaded: E11, row: 11, replies: [
      { speech: 'Rounds set.', display: 'Rounds set.', updates: { epNum: '12', epLen: 115 } }] });
    await W.fn.processUserInput('Work on E12 now — set runtime to 115'); await W.settle();
    ok(W.DB[11].epNum === '11' && W.DB[11].epTitle === 'Little Big Perspectives', 'existing E12: E11 untouched');
    ok(W.ctx.currentEpRow === 12 && W.DB[12].epLen === 115 && W.DB[12].guests[0].name === 'Jimmy George', 'existing E12: switches to row 12 and edits it in place, roster kept');
  }
  // 2b. Switching must start clean: nothing of E11 leaks into E12's saved data.
  {
    const E11full = { ...E11, epThemeDesc: 'E11 THEME', crew: [{ name: 'Kyra Ely' }], prelivePerformer: 'Shanik Hughes' };
    const W = world({ db: { ...BASE_DB, 11: E11full, 12: { epNum: '12', epTitle: 'Little Big Gratitude', guests: [{ name: 'Jimmy George' }] } }, loaded: E11full, row: 11, replies: [
      { speech: 'Set.', display: 'Set.', updates: { epNum: '12', epLen: 115 } }] });
    await W.fn.processUserInput('Work on E12'); await W.settle();
    const e12 = W.DB[12];
    ok(e12.epThemeDesc !== 'E11 THEME' && !(e12.crew || []).some(c => c.name === 'Kyra Ely') && e12.prelivePerformer !== 'Shanik Hughes',
      'switch: none of E11\'s theme, crew or pre-live performer leaks into E12');
  }
  // 2c. A row held by another tool (Boo Producer's row 98) is never claimed for an episode.
  {
    const W = world({ db: BASE_DB, loaded: E11, row: 11, replies: [{ speech: 'Starting.', display: 'Starting.', updates: { epNum: '98', epTitle: 'Ninety-Eight' } }] });
    await W.fn.processUserInput("Let's start E98"); await W.settle();
    ok(W.DB[98].meta === 'Boo Producer season row' && !W.writes.some(w => w.id === 98), 'row collision: Boo Producer\'s row 98 is never written as an episode');
    ok(W.DB[11].epTitle === 'Little Big Perspectives', 'row collision: E11 still untouched');
  }
  // 3. Save guard catches ANY path that renames the loaded episode (not just Boo).
  {
    const W = world({ db: BASE_DB, loaded: E11, row: 11, replies: [] });
    W.ctx.showData.epNum = '12';                     // e.g. a code path that bypasses applyBooUpdates
    await W.fn.saveState();
    ok(!W.writes.some(w => w.id === 11), 'save guard: refuses to write E12 data into E11\'s row');
    ok(W.badges.some(b => /EPISODE MISMATCH/.test(b)), 'save guard: badge says NOT SAVED — EPISODE MISMATCH (never a silent loss)');
  }
  // 4. Unreadable reply (tonight's "12-minute rounds"): never says Done, retries once, changes nothing.
  {
    const cut = W0 => W0;
    const truncated = () => ({ speech: '', display: '', updates: {}, _failed: 'truncated' });
    const W = world({ db: BASE_DB, loaded: E11, row: 11, replies: [truncated(), truncated()] });
    await W.fn.processUserInput("so, let's do 12-minute rounds instead - go for it."); await W.settle();
    const shown = W.booMsgs.join(' ');
    ok(!/Done/.test(shown) && /nothing changed/i.test(shown), 'unreadable reply: never shows "Done" — says plainly that nothing changed');
    ok(W.calls.length === 2 && /cut off/.test(W.calls[1]), 'unreadable reply: retried exactly once, telling Boo why');
    ok(JSON.stringify(W.ctx.showData.cues) === JSON.stringify(E11_CUES), 'unreadable reply: show data unchanged');
  }
  // 5. Unreadable first, good second → applied.
  {
    const W = world({ db: BASE_DB, loaded: { ...E11 }, row: 11, replies: [
      { speech: '', display: '', updates: {}, _failed: 'unparseable' },
      { speech: 'Rounds are in.', display: 'Rounds are in.', updates: { cues: [E11_CUES[0], { scene: 'ROUND 1', dur: 12 }] } }] });
    await W.fn.processUserInput("let's do 12-minute rounds"); await W.settle();
    ok(W.ctx.showData.cues[1].scene === 'ROUND 1' && W.booMsgs.some(m => /✓ Updated: cues/.test(m)), 'retry success: the second reply is applied and shown as ✓ Updated');
  }
  // 6. Boo SAYS it changed something but sends no updates → asks once; applies or admits.
  {
    const W = world({ db: BASE_DB, loaded: { ...E11 }, row: 11, replies: [
      { speech: "Done — four 12-minute rounds are in.", display: "Done — four 12-minute rounds are in.", updates: {} },
      { speech: '', display: '', updates: { cues: [E11_CUES[0], { scene: 'ROUND 1', dur: 12 }] } }] });
    await W.fn.processUserInput('make it four rounds'); await W.settle();
    ok(W.ctx.showData.cues[1].scene === 'ROUND 1' && W.booMsgs.some(m => /✓ Updated: cues/.test(m)), 'claimed change: missing data is fetched and applied');
    const W2 = world({ db: BASE_DB, loaded: { ...E11 }, row: 11, replies: [
      { speech: "Done — rounds are in.", display: "Done — rounds are in.", updates: {} }, { speech: '', display: '', updates: {} }] });
    await W2.fn.processUserInput('make it four rounds'); await W2.settle();
    ok(!W2.booMsgs.some(m => /Done/.test(m)) && W2.booMsgs.some(m => /nothing changed/i.test(m)), 'claimed change: if the data never comes, Mark sees "nothing changed", not "Done"');
  }
  // 7. A plain conversational answer is not mistaken for a failure, and triggers no retries.
  {
    const W = world({ db: BASE_DB, loaded: { ...E11 }, row: 11, replies: [{ speech: 'That shape works — ensemble energy.', display: 'That shape works — ensemble energy.', updates: {} }] });
    await W.fn.processUserInput('what do you think of the shape?'); await W.settle();
    ok(W.calls.length === 1 && W.booMsgs.some(m => /ensemble energy/.test(m)), 'plain answer: shown as-is, no retry, no false alarm');
  }
  // 8. New, unsaved episode given a number that already exists → not saved over it.
  {
    const W = world({ db: BASE_DB, loaded: { epNum: '', cues: [] }, row: 0, replies: [{ speech: 'E11 it is.', display: 'E11 it is.', updates: { epNum: '11', epTitle: 'Oops' } }] });
    await W.fn.processUserInput('11'); await W.settle();
    ok(W.DB[11].epTitle === 'Little Big Perspectives' && !W.writes.some(w => w.id === 11), 'new draft numbered like an existing episode: existing episode untouched');
    ok(W.booMsgs.some(m => /already exists — this draft is NOT saved/.test(m)), 'new draft collision: Mark is told it is NOT saved and why');
  }
  // 8b. Supabase lookup fails mid-"start E12" → nothing claimed blind, nothing overwritten.
  {
    const W = world({ db: { ...BASE_DB, 12: { epNum: '12', epTitle: 'Little Big Gratitude', guests: [{ name: 'Jimmy George' }] } }, loaded: E11, row: 11, replies: [
      { speech: 'Building it.', display: 'Building it.', updates: { epNum: '12', epTitle: 'Something Else', cues: E12_CUES } }] });
    const realFrom = W.ctx.sb.from;
    W.ctx.sb.from = () => { const a = realFrom(); a.lt = () => ({ then(res) { res({ data: null, error: { message: 'network' } }); } }); return a; };
    await W.fn.processUserInput("Let's start E12"); await W.settle();
    ok(W.DB[12].epTitle === 'Little Big Gratitude' && W.DB[11].epTitle === 'Little Big Perspectives', 'lookup failure: neither E11 nor the existing E12 is overwritten');
    ok(W.booMsgs.some(m => /NOT saved/.test(m)), 'lookup failure: Mark is told the draft is NOT saved');
  }
  // 9. Parser contract (pure).
  {
    const W = world({ db: BASE_DB, loaded: E11, row: 11, replies: [] });
    const P = W.fn.parseBooReplyText;
    ok(P('{"speech":"Done","updates":{"cues":[{"scene":"A"', 'max_tokens')._failed === 'truncated', 'parser: cut-off reply → truncated');
    ok(P('{"speech":"Done", updates: oops}', 'end_turn')._failed === 'unparseable', 'parser: broken JSON → unparseable (never passed off as speech)');
    ok(!P('Sure — that works.', 'end_turn')._failed, 'parser: plain text is a normal reply');
    ok(P('```json\n{"speech":"Hi","updates":{"epLen":90}}\n```', 'end_turn').updates.epLen === 90, 'parser: fenced JSON still parses');
  }
  // 10. Dates (pure) — every format Mark has typed, stored one way, never "undefined".
  {
    const W = world({ db: BASE_DB, loaded: E11, row: 11, replies: [] });
    const F = W.fn;
    ok(['2026-11-15', '11/15/2026', '11-15-2026', '11.15.2026', '11/15/26'].every(d => F.normalizeEpDate(d) === '2026-11-15'), 'dates: every typed format stores as 2026-11-15');
    ok(['8/16/2026', '9-13-2026', '2026-06-28'].every(d => !/undefined|NaN/.test(F.formatDateLong(d))), 'dates: E9/E10/E11 dates all render (no "undefined…NaN")');
    ok(F.parseEpDate('Nov 15') === null && F.parseEpDate('2/30/2026') === null && F.formatDateLong('Nov 15') === 'Nov 15', 'dates: unreadable shown as typed, never guessed');
    const W2 = world({ db: BASE_DB, loaded: { ...E11 }, row: 11, replies: [{ speech: 'Set.', display: 'Set.', updates: { epDate: '11-15-2026' } }] });
    await W2.fn.processUserInput('date is 11-15-2026'); await W2.settle();
    ok(W2.ctx.showData.epDate === '2026-11-15', 'dates: a date Boo sets is stored normalized');
  }

  // 10b. Boo on the crew list is the system, not a person to text.
  {
    const W = world({ db: BASE_DB, loaded: E11, row: 11, replies: [] });
    const B = W.fn.isBooCrew;
    ok(B({ name: 'Boo Richards' }) && B({ name: 'Boo Richaards' }) && B({ name: 'Boo' }) && !B({ name: 'Booker Ellis' }) && !B({ name: 'Melba Martinez' }),
      'Boo crew: "Boo Richards"/"Boo" recognized as Boo; real people (even "Booker") are not');
    ok(/if \(isBooCrew\(m\)\) return;/.test(extract('preflightEpisode')), 'Boo crew: Pre-Flight skips the no-mobile check for Boo');
  }
  // 11. Structural — the old failure points are gone, the new rules are wired everywhere.
  ok(!/Done — I've updated the show data/.test(src) && !/Done! I've updated the show data/.test(src), 'structural: the hardcoded "Done — I\'ve updated the show data" is gone');
  ok(/=== WHICH EPISODE YOU ARE EDITING ===/.test(src) && /=== NEVER CLAIM A CHANGE YOU DID NOT SEND ===/.test(src), 'structural: Boo\'s prompt carries both rules');
  ok(!/showData\.epDate\s*=(?!=)(?!\s*normalizeEpDate\()/.test(src), 'structural: every assignment to epDate goes through normalizeEpDate');
  ok(/field === 'epNum' && episodeNumberChange\(/.test(extract('epEdit')), 'structural: hand-editing the episode number uses the same fork rule');
  ok((src.match(/setCues\(u\.cues\)/g) || []).length === 1 && !/showData\.guests\s*=\s*fix\./.test(src), 'structural: Boo changes reach showData through applyBooUpdates only');
  for (const f of ['kit-view.html', 'checklist-view.html']) {
    const v = fs.readFileSync(path.join(path.dirname(BEB), f), 'utf8');
    const fm = v.match(/function fmtDate\([\s\S]*?\n/);
    let out = '';
    try { out = vm.runInNewContext(fm[0] + ';[fmtDate("11-15-2026"),fmtDate("8/16/2026")].join("|")'); } catch (e) { out = 'ERR ' + e.message; }
    ok(out === 'November 15th, 2026|August 16th, 2026', `structural: ${f} reads typed dates ("${out}")`);
  }
  ok(/const maxTokens = needsFullOutput \? (\d+)/.test(src) && +src.match(/const maxTokens = needsFullOutput \? (\d+)/)[1] >= 32000, 'structural: full-output replies get room for a whole show (>= 32k tokens)');
  ok(!/_UNUSED_BASE_CUES_REMOVED/.test(fs.readFileSync(path.join(path.dirname(BEB), 'bsm-template.html'), 'utf8')), 'structural: dead E6 demo cues gone from bsm-template');

  process.exit(fails);
})().catch(e => { console.log('FAIL: harness crashed: ' + (e && e.stack || e)); process.exit(99); });
