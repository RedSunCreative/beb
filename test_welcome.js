#!/usr/bin/env node
// Welcome Kit contract checks. Usage: node test_welcome.js [path/to/welcome-kit.js]
// Prints "PASS: ..." / "FAIL: ..." lines; exit code = number of failures.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const modPath = path.resolve(process.argv[2] || './welcome-kit.js');
let fails = 0;
const ok = (c, m) => { console.log((c ? 'PASS: ' : 'FAIL: ') + m); if (!c) fails++; };
let W;
try { delete require.cache[modPath]; W = require(modPath); }
catch (e) { ok(false, 'welcome-kit.js loads: ' + e.message); process.exit(1); }

const e12 = JSON.parse(fs.readFileSync(path.join(__dirname, 'welcome-e12.json'), 'utf8'));
const html = W.renderWelcomeKit(e12);

// 1. Dates Mark actually types all read the same; garbage reads as null, never "undefined".
const want = 'Sunday, November 15, 2026';
ok(['2026-11-15', '11/15/2026', '11-15-2026'].every(d => W.fmtDateLong(d) === want), 'date: ISO, m/d/y and m-d-y all → ' + want);
ok(W.parseEpDate('Nov 15') === null && W.parseEpDate('2026-02-30') === null, 'date: unreadable/impossible date → null, not a guess');
ok(!/undefined|NaN/.test(W.renderWelcomeKit({ ...e12, epDate: '8/16/2026' })), 'date: E10-style date never renders undefined/NaN');

// 2. Every time on the E12 kit reaches the page.
for (const s of ['Musical Guests Call Time and Sound Check:</b> 3:30 pm', 'Pod Guests Call Time:</b> 4:00 pm', '4:30 pm', '5:00 pm - 6:55 pm', '7:15 pm'])
  ok(html.includes(s), 'E12 times: "' + s + '" on the page');
ok(html.includes('What am I grateful for now, that at the time, I did not see as a gift?'), 'E12: wondering question on the page');
ok(html.includes('Melba Martinez') && html.includes('512-293-3593'), 'E12: green room host + guest services phone on the page');
ok(html.includes('window.print()') && /@media print\{[\s\S]*\.print-btn(,[.\w-]+)*\{display:none\}/.test(html), 'printable: print button present and hidden in print');

// 2b. One spacing system: no blank-line spacers, no one-off inline styles in the body.
const body = html.slice(html.indexOf('<body>'));
ok(!/&nbsp;/.test(body) && !/style="/.test(body), 'spacing: no &nbsp; spacers or inline styles in the page body');
ok(html.includes('make up and hair products'), 'E12: hair + makeup line on the page');
ok(html.includes('but just wondering it will be your best preparation!'), 'E12: theme closing line as Mark wrote it');
ok(html.includes('we hope you\u2019ll stay!)') && ['Your authentic self.', 'peaceful and comfortable.', 'who you are.'].every(x => html.includes(x + '</li>')), 'E12: dinner line + bring/wear punctuation as Mark wrote it');
const split = W.renderWelcomeKit({ ...e12, times: { ...e12.times, musicCall: '15:15', soundCheck: '15:30' } });
ok(split.includes('Musical Guests Call Time:</b> 3:15 pm, Sound Check at 3:30 pm'), 'music line: separate call + sound check when they differ');
for (const a of new Set(html.match(/assets\/[\w.-]+/g) || []))
  ok(fs.existsSync(path.join(__dirname, a)), 'asset exists: ' + a);

ok(/\.signature\{font-family:'Allison'/.test(html) && /family=Allison/.test(html) && !html.includes('\u2014--'), 'signature: Allison script loaded and used, no dash line');

ok(html.includes('GO LIVE Time and Date: 5:00 pm CT, Sunday, November 15, 2026'), 'E12: GO LIVE time and date line as Mark wrote it');

ok(html.includes('You might or might not share your response'), 'E12: "might or might not" as Mark wrote it');
ok(/@bottom-right\{content:counter\(page\)/.test(html), 'print: page number bottom right');
ok(/@bottom-left\{content:"LBV LIVE! Welcome Kit/.test(html), 'print: kit name in the footer of every page');

ok(html.includes("You're here because you are a YES! Mark invited you") && html.includes('hold space for you to share it.'), 'E12: "Why You\'re Here" as Mark wrote it');

ok(html.includes("curious about another's stories or experiences. Thank you for sharing yours!"), 'E12: "Please Remember" as Mark wrote it');

ok(/<div class="sig-row">[\s\S]*?class="signature"[\s\S]*?<img class="card"[\s\S]*?<\/div>\s*<\/section>/.test(html) && /@media print\{[\s\S]*\.sig-row\{flex-wrap:nowrap\}/.test(html),
  'print: Mark\'s card sits beside the signature (phone prints never spill it onto a blank page)');

// 3. Show data is escaped at every interpolation.
const evil = '<img src=x onerror=alert(1)>';
const hostile = { ...e12, epNum: evil, epTitle: evil, wonderingQuestion: evil, greenRoomHost: evil, greenRoomHostPronoun: evil,
  cameraNote: evil, guestListNote: evil, themeIntro: evil, themeOutro: evil, watchURL: 'https://x"' + evil,
  guestServices: { name: evil, phone: evil } };
ok(!W.renderWelcomeKit(hostile).includes('<img src=x'), 'escaping: hostile text in every field stays inert');

// 4. Gaps block the kit — nothing goes to a guest with a hole in it.
const g = W.welcomeKitGaps({ ...e12, wonderingQuestion: '', epDate: '8/16', times: { ...e12.times, podCall: '' } });
ok(g.some(x => /wondering/.test(x)) && g.some(x => /air date/.test(x)) && g.some(x => /pod call/.test(x)), 'gaps: missing question / bad date / missing call time all reported');
ok(W.welcomeKitGaps(e12).length === 0, 'gaps: complete E12 kit reports none');

// 5. The published page is what the template + data produce (no hand edits, no stale build).
const pub = path.join(__dirname, 'welcome-e12.html');
if (modPath === path.resolve(__dirname, 'welcome-kit.js')) {
  ok(fs.existsSync(pub) && fs.readFileSync(pub, 'utf8') === html, 'freshness: welcome-e12.html == render(welcome-e12.json)');
  const tmp = path.join(require('os').tmpdir(), 'wk-gap-' + process.pid + '.json');
  fs.writeFileSync(tmp, JSON.stringify({ ...e12, epNum: '99x', wonderingQuestion: '' }));
  const r = cp.spawnSync('node', [path.join(__dirname, 'build-welcome.js'), tmp], { cwd: require('os').tmpdir() });
  ok(r.status === 1 && !fs.existsSync(path.join(require('os').tmpdir(), 'welcome-e99x.html')), 'builder: refuses to write a kit with gaps');
  fs.unlinkSync(tmp);
}
process.exit(fails);
