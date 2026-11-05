#!/usr/bin/env node
// Live-show pointer + wake/reconnect resync — contract tests against the REAL bsm-live.js and the
// REAL functions in bsm-template.html (extracted verbatim), with Supabase / network / clock simulated.
//   node test_live_pointer.js [dir]     (dir holds bsm-live.js, bsm-template.html, tv/crew/host.html)
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const DIR = path.resolve(process.argv[2] || __dirname);
let fails = 0;
const ok = (c, m) => { console.log((c ? 'PASS: ' : 'FAIL: ') + m); if (!c) fails++; };
const read = f => fs.readFileSync(path.join(DIR, f), 'utf8');

// ── A. permanent screens (bsm-live.js) ──────────────────────────────────────────────────────
function loadLive() {
  const m = { exports: {} };
  vm.runInNewContext(read('bsm-live.js'), { module: m, URLSearchParams, encodeURIComponent, String, globalThis: {} });
  return m.exports;
}
function liveWorld({ view = 'tv', search = '', pointer = null, tableMissing = false, rows = {}, files = {} }) {
  const W = { pointer, tableMissing, rows, files, offline: false, handlers: {}, subscribeCb: null, intervals: [], srcLog: [], slow: null };
  const el = id => (W[id] = W[id] || { id, style: {}, textContent: '', _src: '', set src(v) { this._src = v; if (id === 'live-frame') W.srcLog.push(v); }, get src() { return this._src; } });
  const q = (table) => {
    const st = { table, id: null };
    const api = {
      select() { return api; }, eq(_, v) { st.id = v; return api; },
      maybeSingle: async () => {
        const ptrAtRead = W.pointer, missingAtRead = W.tableMissing;   // value as of the read, like a real slow query
        if (W.slow) await W.slow;
        if (st.table === 'bsm_settings') return missingAtRead ? { data: null, error: { message: 'relation does not exist' } } : { data: { live_show_id: ptrAtRead }, error: null };
        const r = W.rows[st.id]; return { data: r ? { epNum: r } : null, error: null };
      },
    };
    return api;
  };
  W.sb = {
    from: q,
    channel: () => { const ch = { on(_, __, cb) { W.rtHandler = cb; return ch; }, subscribe(cb) { W.subscribeCb = cb; return ch; } }; return ch; },
  };
  W.fetchFn = async (file) => {
    if (W.offline) throw new Error('offline');
    const f = W.files[file];
    return f ? { ok: true, headers: { get: n => (n === 'etag' ? f : '') } } : { ok: false, headers: { get: () => '' } };
  };
  W.doc = { visibilityState: 'visible', getElementById: el, addEventListener: (ev, cb) => { W.handlers['doc:' + ev] = cb; } };
  W.win = { addEventListener: (ev, cb) => { W.handlers['win:' + ev] = cb; }, setInterval: (f, ms) => { W.intervals.push({ f, ms }); return W.intervals.length; }, clearInterval: (id) => { if (W.intervals[id - 1]) W.intervals[id - 1].cleared = true; } };
  W.screen = loadLive().createLiveScreen({ sb: W.sb, fetchFn: W.fetchFn, doc: W.doc, win: W.win, view, search });
  W.frame = () => W['live-frame']; W.hold = () => W['holding'];
  W.wake = async () => { W.doc.visibilityState = 'visible'; await W.handlers['doc:visibilitychange'](); };
  return W;
}

(async () => {
  const { decideScreen } = loadLive();
  ok(decideScreen({ view: 'tv', pointerSetup: true, pointerEpNum: '' }).mode === 'holding', 'decide: no live show → holding screen');
  ok(decideScreen({ view: 'tech', pointerSetup: true, pointerEpNum: '12', fileOk: true, fileVersion: 'W/"a"' }).src === 'bsm-e12.html?view=tech&embed=1&v=W%2F%22a%22', 'decide: live E12 on crew → bsm-e12.html?view=tech');
  ok(decideScreen({ view: 'tv', pointerSetup: false }).reason === 'not-set-up', 'decide: settings table missing → holding (not set up), never an error page');
  ok(decideScreen({ view: 'host', pinnedEp: '11', pointerSetup: false, fileOk: true }).src.startsWith('bsm-e11.html?view=host'), 'decide: ?show=11 pins E11 even with no settings table');
  ok(decideScreen({ view: 'tv', pointerSetup: true, pointerEpNum: '12', fileOk: false }).reason === 'not-published', 'decide: live episode not published yet → holding');
  ok(decideScreen({ view: 'tv', pinnedEp: '12;alert(1)' }).mode === 'holding', 'decide: junk in ?show= → holding, never a crafted URL');

  {
    const W = liveWorld({ pointer: null, rows: { 12: '12' }, files: { 'bsm-e12.html': 'A' } });
    await W.screen.start();
    ok(W.hold().style.display === 'flex' && W.frame().style.display === 'none', 'screen: empty pointer → LBV holding screen');
    W.pointer = 12; await W.rtHandler();
    ok(W.frame().src === 'bsm-e12.html?view=tv&embed=1&v=A' && W.hold().style.display === 'none', 'screen: "Set as live" (Realtime) → switches to E12 Studio view');
    W.rows[11] = '11'; W.files['bsm-e11.html'] = 'B'; W.pointer = 11; await W.rtHandler();
    ok(W.frame().src.startsWith('bsm-e11.html?view=tv'), 'screen: pointer moves to E11 → switches automatically');
    const before = W.srcLog.length; await W.rtHandler();
    ok(W.srcLog.length === before, 'screen: unchanged pointer does not reload the show (no flicker mid-show)');
    W.pointer = null; await W.rtHandler();
    ok(W.hold().style.display === 'flex' && W.frame().src === 'about:blank', 'screen: pointer cleared → back to holding screen');
  }
  {
    const W = liveWorld({ pointer: 12, rows: { 12: '12', 10: '10' }, files: { 'bsm-e12.html': 'A', 'bsm-e10.html': 'C' } });
    await W.screen.start();
    W.pointer = 10;                                   // changed while the tablet slept — no Realtime event seen
    W.doc.visibilityState = 'hidden'; await W.wake();
    ok(W.frame().src.startsWith('bsm-e10.html'), 'wake: pointer changed during sleep → correct show on wake');
    W.files['bsm-e10.html'] = 'C2'; await W.wake();
    ok(W.frame().src.endsWith('&v=C2'), 'wake: episode republished during sleep → fresh copy loaded');
    W.pointer = 12; await W.handlers['win:online']();
    ok(W.frame().src.startsWith('bsm-e12.html'), 'network back online → re-checks and switches');
  }
  {
    const W = liveWorld({ pointer: 12, rows: { 12: '12', 11: '11' }, files: { 'bsm-e12.html': 'A', 'bsm-e11.html': 'B' } });
    await W.screen.start();
    W.subscribeCb('SUBSCRIBED');                      // first connect — no extra refresh needed
    W.subscribeCb('CHANNEL_ERROR');
    ok(W.intervals.some(i => i.ms === 15000 && !i.cleared), 'reconnect: Realtime drop starts 15 s polling');
    W.pointer = 11;
    W.subscribeCb('SUBSCRIBED'); await new Promise(r => setImmediate(r)); await new Promise(r => setImmediate(r));
    ok(W.frame().src.startsWith('bsm-e11.html'), 'reconnect: Realtime reconnect re-reads the pointer (missed change caught)');
    ok(W.intervals.filter(i => i.ms === 15000).every(i => i.cleared), 'reconnect: polling stops once Realtime is back');
    ok(W.intervals.some(i => i.ms === 60000), 'safety: a 60 s background check runs even if every event is missed');
  }
  {
    const W = liveWorld({ search: '?show=12', pointer: 11, tableMissing: true, rows: { 11: '11' }, files: { 'bsm-e12.html': 'A', 'bsm-e11.html': 'B' } });
    await W.screen.start();
    ok(W.frame().src.startsWith('bsm-e12.html?view=tv'), 'pinned: ?show=12 shows E12 regardless of the pointer');
    W.tableMissing = false; await W.rtHandler(); await W.wake();
    ok(W.frame().src.startsWith('bsm-e12.html'), 'pinned: stays on E12 when the pointer changes');
  }
  {
    const W = liveWorld({ pointer: 12, rows: { 12: '12' }, files: { 'bsm-e12.html': 'A' } });
    await W.screen.start();
    const loads = W.srcLog.length;
    W.offline = true; await W.wake();
    ok(W.frame().src.startsWith('bsm-e12.html') && W.frame().style.display === 'block' && W.srcLog.length === loads, 'offline on wake: keeps the live show up — no reload into a dead page');
    const W2 = liveWorld({ pointer: 13, rows: { 13: '13' }, files: {} }); await W2.screen.start();
    ok(W2.hold().style.display === 'flex', 'not published: live E13 with no bsm-e13.html → holding, not a 404 page');
    const W3 = liveWorld({ tableMissing: true }); await W3.screen.start();
    ok(W3.hold().style.display === 'flex', 'not set up: before the SQL is applied every screen shows the holding screen');
  }
  {
    let release; const W = liveWorld({ pointer: 12, rows: { 12: '12', 11: '11' }, files: { 'bsm-e12.html': 'A', 'bsm-e11.html': 'B' } });
    W.slow = new Promise(r => { release = r; });
    const older = W.screen.refresh();                 // slow read of the OLD pointer (12)…
    W.slow = null; W.pointer = 11; await W.screen.refresh();   // …overtaken by a fast read of the new one
    release(); await older;
    ok(W.frame().src.startsWith('bsm-e11.html'), 'race: a slow stale refresh never overwrites a newer one');
  }
  for (const [f, v] of [['tv.html', 'tv'], ['crew.html', 'tech'], ['host.html', 'host']]) {
    const h = read(f);
    ok(h.includes(`window.BSM_LIVE_VIEW='${v}'`) && h.includes('src="bsm-live.js"') && h.includes('id="live-frame"') && h.includes('id="holding"') && h.includes('screen-wake-lock'),
      `pages: ${f} opens the ${v} view through the shared bsm-live.js`);
  }

  // ── B. bsm-template.html ─────────────────────────────────────────────────────────────────
  const tpl = read('bsm-template.html');
  const js = tpl.slice(tpl.indexOf('<script>\nconst SB_URL'), tpl.lastIndexOf('</script>'));
  function grab(name) {
    const re = new RegExp('(?:^|\\n)(async function|function) ' + name + '\\(');
    const m = re.exec(js); if (!m) throw new Error('MISSING ' + name);
    const i = m.index + (js[m.index] === '\n' ? 1 : 0);
    const end = js.indexOf('\n}', i); return js.slice(i, end + 2);
  }
  let T;
  try { T = ['tickOnce', 'tick', 'startTicking', 'resyncAll', 'myEpisodeRow', 'readLivePointer', 'renderLivePointer', 'setAsLive', 'startRealtime', 'startFallbackPoll'].map(grab).join('\n'); }
  catch (e) { ok(false, 'template: extract functions — ' + e.message); T = null; }
  if (T) {
    const make = (over = {}) => {
      const S = { rendered: 0, applied: [], writes: [], alerts: [], confirms: true, now: 1e12, subCb: null, rt: [], rowsByEp: { '12': [{ id: 12 }] }, ptr: 12 };
      const ctx = {
        Date: Object.assign(function (...a) { return a.length ? new Date(...a) : new Date(S.now); }, { now: () => S.now, parse: Date.parse }), Math, String, Number, console: { error() {} }, alert: m => S.alerts.push(m), confirm: () => S.confirms,
        document: { querySelectorAll: () => [], getElementById: () => null }, setInterval: () => 7, clearInterval() {},
        render: () => S.rendered++, startBooSlowFlash() {}, stopBooFlash() {}, setFlashRate() {}, setSyncBadge() {},
        applyRemoteState: (s, o) => S.applied.push({ s, o }),
        sbGet: async () => S.remote, EPISODE: { num: '12' }, CUES: [{ w5: 'w5', w2: 'w2' }], cueIdx: 0,
        segSecs: 400, showSecs: 5000, showTimerStarted: true, warning: null, timerInt: 0, _lastTickAt: 0, lastLocalWriteAt: 0,
        view: 'tv', _poll: null, _everSubscribed: false, livePtr: { setup: null, row: null, myRow: undefined }, running: true,
        sbClient: {
          from: (t) => { const st = { t, filt: {} }; const a = {
            select() { return a; }, eq(k, v) { st.filt[k] = v; return a; },
            update(p) { st.update = p; return a; },
            maybeSingle: async () => ({ data: { live_show_id: S.ptr }, error: null }),
            then(res) { if (st.update) { S.writes.push({ t: st.t, p: st.update, filt: st.filt }); res({ error: null }); }
                        else res({ data: S.rowsByEp[st.filt['data->>epNum']] || [], error: null }); },
          }; return a; },
          channel: () => { const ch = { on(_, f, cb) { S.rt.push(f.table); return ch; }, subscribe(cb) { S.subCb = cb; return ch; } }; return ch; },
        },
        ...over,
      };
      vm.createContext(ctx); vm.runInContext(T, ctx); ctx.S = S; return ctx;
    };
    { // sleep catch-up
      const c = make(); c._lastTickAt = c.S.now; c.S.now += 330 * 1000; c.tick();
      ok(c.segSecs === 70 && c.showSecs === 4670, 'timers: 330 s of sleep → countdown catches up by exactly 330 s');
      ok(c.warning === '2' && c.S.rendered === 1, 'timers: warnings inside the sleep gap still fire; one repaint, not 330');
      const c2 = make(); c2._lastTickAt = c2.S.now; c2.S.now += 400; c2.tick();
      ok(c2.segSecs === 400 && c2.S.rendered === 0, 'timers: an early interval callback never double-counts a second');
    }
    { // host adopts only NEWER remote state
      const c = make({ view: 'host' }); c.lastLocalWriteAt = Date.parse('2026-11-15T23:10:00Z');
      c.S.remote = { updated_at: '2026-11-15T23:09:00Z' }; await c.resyncAll();
      ok(c.S.applied.length === 0, 'Producer wake: its own (or older) state is not re-applied over itself');
      c.S.remote = { updated_at: '2026-11-15T23:12:00Z' }; await c.resyncAll();
      ok(c.S.applied.length === 1 && c.S.applied[0].o && c.S.applied[0].o.force, 'Producer wake: another Producer device moved the show → adopts it');
      const t = make({ view: 'tech' }); t.S.remote = { updated_at: '2026-11-15T23:09:00Z' }; await t.resyncAll();
      ok(t.S.applied.length === 1, 'Crew/Studio wake: always re-applies the latest show state');
    }
    { // reconnect → resync
      const c = make(); let n = 0; c.resyncAll = async () => { n++; }; c.startRealtime();
      c.S.subCb('SUBSCRIBED'); c.S.subCb('CHANNEL_ERROR'); c.S.subCb('SUBSCRIBED');
      ok(n === 1, 'Realtime: re-sync on RE-connect only (not on the first connect)');
      ok(c.S.rt.includes('show_state') && c.S.rt.includes('bsm_settings'), 'Realtime: listens to show_state and the live pointer');
    }
    { // Set as live
      const c = make(); c.S.ptr = null; await c.setAsLive();
      const w = c.S.writes.find(x => x.t === 'bsm_settings');
      ok(w && w.p.live_show_id === 12 && w.filt.id === 1, 'Set as live: writes THIS episode\'s builder_state row (12) to the single settings row');
      const c2 = make(); c2.S.confirms = false; await c2.setAsLive();
      ok(!c2.S.writes.length, 'Set as live: cancelling the confirm writes nothing');
      const c3 = make(); c3.S.rowsByEp = { '12': [{ id: 12 }, { id: 99 }] }; await c3.setAsLive();
      ok(!c3.S.writes.length && c3.S.alerts.length === 1, 'Set as live: ambiguous episode (two rows) → refuses and says so');
    }
  }
  ok(!/timerInt=setInterval\(tick,1000\)/.test(js.replace(grab('startTicking'), '')), 'template: every timer start goes through startTicking (wall clock)');
  ok(/visibilitychange[\s\S]{0,400}resyncAll\(\)/.test(js), 'template: page becoming visible re-syncs every view (Producer included)');
  ok(/const _qv=new URLSearchParams\(location\.search\)\.get\('view'\)/.test(js) && /if\(_qv==='host'\) tryHost\(\)/.test(js), 'template: ?view= opens Studio/Crew/Producer directly (Producer still asks for the PIN)');
  const views = {}; let curView = null;
  for (const line of tpl.split('\n')) { const m = line.match(/id="view-([a-z-]+)"/); if (m) curView = m[1]; if (line.includes('class="live-ptr"')) views[curView] = true; }
  ok(views['tech-welcome'] && views['tech'] && !views['tv'] && !views['tv-welcome'] && !views['host'], 'template: "Set as live" lives only in the Crew views, never on the public Studio TV');

  // ── C. the migration ───────────────────────────────────────────────────────────────────
  const sql = fs.readdirSync(path.join(DIR, 'supabase', 'migrations')).filter(f => /bsm_settings\.sql$/.test(f)).map(f => read(path.join('supabase', 'migrations', f))).join('\n');
  const body = sql.replace(/--.*$/gm, '');
  ok(/create table public\.bsm_settings/.test(body) && /check \(id = 1\)/.test(body) && /references public\.builder_state\(id\) on delete set null/.test(body), 'SQL: single-row bsm_settings, live_show_id → builder_state(id)');
  ok(/enable row level security/.test(body) && /for select/.test(body) && /for update/.test(body) && !/for (insert|delete|all)/.test(body), 'SQL: RLS — read + update only, no insert/delete');
  ok(/alter publication supabase_realtime add table public\.bsm_settings/.test(body), 'SQL: table published to Realtime');
  ok(!/\b(drop|truncate|delete from|alter table (?!public\.bsm_settings))\b/i.test(body) && /^\s*begin;[\s\S]*commit;\s*$/m.test(body), 'SQL: additive only, in one transaction — touches no existing table');

  process.exit(fails);
})().catch(e => { console.log('FAIL: harness crashed: ' + (e && e.stack || e)); process.exit(99); });
