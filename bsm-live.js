// Permanent BSM screens — tv.html (Studio), crew.html (Crew/Tech), host.html (Producer).
// One URL per view that never changes between episodes. Reads bsm_settings.live_show_id (an
// episode's builder_state row), shows that episode's published BSM in the right view, and follows
// the pointer live:
//   • Realtime: switches the moment "Set as live" is pressed
//   • page becomes visible again (phones/tablets waking) / network comes back / Realtime
//     reconnects: re-reads the pointer AND re-checks the published file, so nothing stays stale
//   • a quiet 60 s safety check, and 15 s polling while Realtime is down
// No live show → LBV holding screen. ?show=12 pins episode 12 and ignores the pointer.
(function (root) {
  'use strict';

  // Pure: what should the screen show?  → { mode:'holding', reason } | { mode:'show', file, src }
  function decideScreen(o) {
    const view = o.view === 'tech' || o.view === 'host' ? o.view : 'tv';
    const epNum = o.pinnedEp ? String(o.pinnedEp).trim() : (o.pointerEpNum == null ? '' : String(o.pointerEpNum).trim());
    if (!o.pinnedEp && o.pointerSetup === false) return { mode: 'holding', reason: 'not-set-up' };
    if (!epNum || !/^\d+$/.test(epNum)) return { mode: 'holding', reason: o.pinnedEp ? 'bad-pin' : 'no-live-show' };
    const file = `bsm-e${epNum}.html`;
    if (o.fileOk === false) return { mode: 'holding', reason: 'not-published', file };
    const v = o.fileVersion ? `&v=${encodeURIComponent(o.fileVersion)}` : '';
    return { mode: 'show', file, src: `${file}?view=${view}&embed=1${v}` };
  }

  function createLiveScreen(env) {
    const { sb, fetchFn, doc, win, view, search } = env;
    const pinnedEp = new URLSearchParams(search || '').get('show');
    const frame = doc.getElementById('live-frame');
    const holding = doc.getElementById('holding');
    const statusEl = doc.getElementById('holding-status');
    let current = null, seq = 0, everSubscribed = false, pollTimer = null;

    async function readPointer() {
      try {
        const { data, error } = await sb.from('bsm_settings').select('live_show_id').eq('id', 1).maybeSingle();
        if (error || !data) throw (error || new Error('no settings row'));
        if (data.live_show_id == null) return { setup: true, epNum: '' };
        const r = await sb.from('builder_state').select('data->>epNum').eq('id', data.live_show_id).maybeSingle();
        if (r.error) throw r.error;
        const epNum = r.data ? (r.data.epNum != null ? r.data.epNum : r.data['data->>epNum']) : '';
        return { setup: true, epNum: epNum || '' };
      } catch (e) { return { setup: false, epNum: '' }; }
    }
    async function checkFile(file) {
      try {
        const res = await fetchFn(file, { method: 'HEAD', cache: 'no-store' });
        if (!res.ok) return { ok: false };
        const h = n => (res.headers && res.headers.get ? res.headers.get(n) : '') || '';
        return { ok: true, version: h('etag') || h('last-modified') };
      } catch (e) { return { ok: null }; }       // offline: keep whatever is on screen
    }

    async function refresh() {
      const my = ++seq;
      const ptr = pinnedEp ? { setup: true, epNum: pinnedEp } : await readPointer();
      let fileOk, fileVersion;
      const ep = pinnedEp || ptr.epNum;
      if (ep && /^\d+$/.test(String(ep))) {
        const f = await checkFile(`bsm-e${ep}.html`);
        if (f.ok === null) { if (my === seq && current) return current; }   // offline → don't blank a live screen
        fileOk = f.ok; fileVersion = f.version;
      }
      if (my !== seq) return current;           // a newer refresh started — let it win
      const d = decideScreen({ view, pinnedEp, pointerSetup: ptr.setup, pointerEpNum: ptr.epNum, fileOk, fileVersion });
      apply(d);
      return d;
    }

    function apply(d) {
      const same = current && current.mode === d.mode && current.src === d.src && current.reason === d.reason;
      current = d;
      if (same) return;
      if (d.mode === 'show') {
        frame.src = d.src;
        frame.style.display = 'block';
        holding.style.display = 'none';
      } else {
        frame.style.display = 'none';
        frame.src = 'about:blank';
        holding.style.display = 'flex';
        if (statusEl) statusEl.textContent = d.reason === 'not-published' ? 'waiting for this episode to publish'
          : d.reason === 'not-set-up' ? 'live screens not set up yet' : 'waiting for the live show';
      }
    }

    function startPoll() { if (!pollTimer) pollTimer = win.setInterval(refresh, 15000); }
    function stopPoll() { if (pollTimer) { win.clearInterval(pollTimer); pollTimer = null; } }

    function subscribe() {
      sb.channel('bsm_live_pointer')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'bsm_settings' }, () => refresh())
        .subscribe(status => {
          if (status === 'SUBSCRIBED') { stopPoll(); if (everSubscribed) refresh(); everSubscribed = true; }
          else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') startPoll();
        });
    }

    function start() {
      doc.addEventListener('visibilitychange', () => (doc.visibilityState === 'visible' ? refresh() : undefined));
      win.addEventListener('online', () => refresh());
      win.addEventListener('pageshow', e => { if (e && e.persisted) refresh(); });   // back/forward cache
      win.setInterval(refresh, 60000);
      subscribe();
      return refresh();
    }

    return { start, refresh, get current() { return current; } };
  }

  const api = { decideScreen, createLiveScreen };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else {
    root.BSMLive = api;
    root.addEventListener('DOMContentLoaded', () => {
      const SB_URL = 'https://gogudwpuhmidngsbqfjg.supabase.co';
      const SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdvZ3Vkd3B1aG1pZG5nc2JxZmpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3MTQ2NTMsImV4cCI6MjA5NDI5MDY1M30.O6n_tRQsMU29wFV_RArcN9n6gP8KSDWJQqM4P6cTq3s';
      const sb = root.supabase.createClient(SB_URL, SB_KEY);
      createLiveScreen({ sb, fetchFn: root.fetch.bind(root), doc: root.document, win: root,
        view: root.BSM_LIVE_VIEW, search: root.location.search }).start();
    });
  }
})(typeof window !== 'undefined' ? window : globalThis);
