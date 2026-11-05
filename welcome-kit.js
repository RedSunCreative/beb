// LBV Guest Welcome Kit — the ONE template.
// Used by build-welcome.js today (→ welcome-e{N}.html) and, next, by beb.html
// (Preview / per-guest link / Publish). Do not grow a second copy of this text.
//
// renderWelcomeKit(kit) is pure: data in, complete HTML document out. Every
// interpolation of show data goes through esc().
(function (root) {
  'use strict';

  const DEFAULT_ASSET_BASE = 'https://redsuncreative.github.io/beb/assets/';
  const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  const DAYS = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // Accepts the formats Mark has actually typed: 2026-11-15, 11/15/2026, 11-15-2026.
  // Returns null when it can't tell — callers must treat that as an error, never guess.
  function parseEpDate(s) {
    if (!s) return null;
    const t = String(s).trim();
    let y, m, d, mm;
    if ((mm = t.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/))) { y = +mm[1]; m = +mm[2]; d = +mm[3]; }
    else if ((mm = t.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/))) { m = +mm[1]; d = +mm[2]; y = +mm[3]; }
    else return null;
    const dt = new Date(Date.UTC(y, m - 1, d));
    if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
    return dt;
  }

  function fmtDateLong(s) {
    const dt = parseEpDate(s);
    if (!dt) return '';
    return `${DAYS[dt.getUTCDay()]}, ${MONTHS[dt.getUTCMonth()]} ${dt.getUTCDate()}, ${dt.getUTCFullYear()}`;
  }

  // "17:00" → "5:00 pm". Empty/invalid → ''.
  function fmtTime(t) {
    const mm = String(t || '').match(/^(\d{1,2}):(\d{2})$/);
    if (!mm) return '';
    let h = +mm[1];
    const ap = h >= 12 ? 'pm' : 'am';
    h = h % 12 || 12;
    return `${h}:${mm[2]} ${ap}`;
  }

  const DEFAULT_THEME_INTRO = 'We’ll be exploring what happens when some real people from different backgrounds, cultures, and beliefs get together to deeply listen to each other and contemplate our wondering question for this episode:';
  const DEFAULT_THEME_OUTRO = 'You may or may not share your response on the show - that’s up to you - but just wondering it will be your only preparation!';
  const DEFAULT_GUEST_LIST = 'As the studio is “intimate”, and with the number of guests this episode, we are intentional about who else joins beyond the guests and crew - that said, we’ll make room for those you feel would benefit from being here - or that you feel important to support you. Please just let {gs} know ahead of time and we’ll plan accordingly!';

  // Fields the kit can't be sent without. Returned as human-readable gaps.
  function welcomeKitGaps(k) {
    const gaps = [];
    if (!k.epNum) gaps.push('episode number');
    if (!k.epTitle) gaps.push('episode title / theme');
    if (!parseEpDate(k.epDate)) gaps.push(k.epDate ? `air date "${k.epDate}" (can't read it)` : 'air date');
    if (!k.wonderingQuestion) gaps.push('wondering question');
    const t = k.times || {};
    if (!fmtTime(t.goLive)) gaps.push('go-live time');
    if (!fmtTime(t.musicCall)) gaps.push('music call time');
    if (!fmtTime(t.podCall)) gaps.push('pod call time');
    if (!fmtTime(t.circle)) gaps.push('show circle time');
    if (!k.guestServices || !k.guestServices.name) gaps.push('guest services contact');
    return gaps;
  }

  function renderWelcomeKit(k, opts) {
    const assetBase = (opts && opts.assetBase) || DEFAULT_ASSET_BASE;
    const t = k.times || {};
    const gs = k.guestServices || {};
    const gsFirst = (gs.name || '').split(' ')[0] || 'Melissa';
    const host = k.greenRoomHost || '';
    const dateLong = fmtDateLong(k.epDate);
    const watchURL = k.watchURL || 'https://littlebigvoices.com';
    const watchLabel = watchURL.replace(/^https?:\/\//, '').replace(/\/$/, '');
    const showEnd = fmtTime(t.showEnd);
    const goLive = fmtTime(t.goLive);
    const guestList = (k.guestListNote || DEFAULT_GUEST_LIST).replace('{gs}', gsFirst);

    const li = (label, val, extra) => val ? `<li><b>${esc(label)}:</b> ${esc(val)}${extra || ''}</li>` : '';
    const musicCall = fmtTime(t.musicCall);
    const soundCheck = fmtTime(t.soundCheck);

    return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Allison&display=swap" rel="stylesheet">
<title>Little Big Voices LIVE Guest Welcome Kit — Episode ${esc(k.epNum)}</title>
<meta property="og:title" content="You're invited — Little Big Voices LIVE! Episode ${esc(k.epNum)}: ${esc(k.epTitle)}">
<meta property="og:description" content="${esc(dateLong)}${goLive ? ' · Go live ' + esc(goLive) + ' CT' : ''}. Your Guest Welcome Kit.">
<meta property="og:image" content="${assetBase}lbv-welcome-cover-qr.jpg">
<style>
  /* One spacing system. --gap: between sections. --space: between blocks inside a section.
     Both in em so screen, phone and print keep the same rhythm. Nothing else sets vertical margins. */
  *{box-sizing:border-box;margin:0;padding:0}
  :root{--orange:#F29A1F;--ink:#1d1d1d;--gap:1.4em;--space:.6em}
  body{font-family:Arial,Helvetica,sans-serif;color:var(--ink);background:#f4f1ec;font-size:16px;line-height:1.5}
  .page{position:relative;max-width:8.5in;margin:24px auto;background:#fff;padding:48px 56px;box-shadow:0 2px 18px rgba(0,0,0,.08)}
  .print-btn{position:absolute;top:20px;right:20px;background:var(--orange);color:#fff;border:0;border-radius:6px;padding:10px 18px;font:700 14px Arial,sans-serif;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,.15)}
  .cover{display:block;width:340px;max-width:80%;margin:0 auto var(--gap)}
  h1{color:var(--orange);font-size:1.5em;line-height:1.25;text-align:center}
  h2,.label{color:var(--orange);font-weight:700}
  h2{font-size:1.06em}
  section{margin-top:var(--gap);break-inside:avoid;page-break-inside:avoid}
  section > * + *{margin-top:var(--space)}
  h2 + *{margin-top:.3em}
  ul{padding-left:1.75em}
  li + li, li > ul{margin-top:.25em}
  ul ul{list-style:circle}
  .theme{color:#444}
  .question{padding:.7em 1em;border-left:4px solid var(--orange);background:#fff7ec;font-size:1.06em;font-style:italic;color:var(--ink)}
  .em{font-style:italic}
  hr{border:0;border-top:1px solid #999;margin-top:var(--gap)}
  .sig .lines{line-height:1.4}
  .signature{font-family:'Allison',cursive;font-size:3.4em;line-height:1;color:#23314f;-webkit-text-stroke:.4px #fff;margin:.1em 0 .15em}
  .card{display:block;width:210px;border:1px solid #222}
  a{color:#1155cc}
  .foot{margin-top:var(--gap);font-size:.75em;color:#888;font-weight:700}
  @media (max-width:640px){.page{margin:0;padding:28px 20px;box-shadow:none}.print-btn{position:static;display:block;width:100%;margin-bottom:var(--gap)}}
  @page{size:letter;margin:0.6in 0.75in}
  @media print{
    body{background:#fff;font-size:11pt}
    :root{--gap:1.15em}
    .page{margin:0;padding:0;box-shadow:none;max-width:none}
    .print-btn{display:none}
    .cover{width:2.6in}
    .card{width:1.7in}
    section.sig{break-inside:auto;page-break-inside:auto}
    .card{break-inside:avoid}
    h2{break-after:avoid;page-break-after:avoid}
  }
</style></head>
<body><div class="page">
<button class="print-btn" onclick="window.print()">Print / Save as PDF</button>
<img class="cover" src="${assetBase}lbv-welcome-cover-qr.jpg" alt="You're invited! littlebigvoices.com — Podcast &amp; Live TV Show">
<h1>Little Big Voices LIVE Guest Welcome Kit: Episode ${esc(k.epNum)}!</h1>

<section>
<h2>Welcome to Little Big Voices LIVE!</h2>
<p><b>What This Show Is About:</b> Little Big Voices creates understanding, compassion, and connection through authentic conversations and performances. We explore the fabric of our shared humanity — discovering that we have more in common than we have differences. This isn't about perfection or performance; it's about being genuinely seen and heard.</p>
<p><b>Why You're Here:</b> Mark invited you because often Spirit will whisper to him who to invite - and often because your story/energy/presence strikes a chord in him—you inspire him and strengthen him as he lives out his story and mission. Also, sharing your experience may do the same for our audience as they navigate their own journeys. Your voice and story matter, and we're honored to hold space for you to express it.</p>
</section>

<section>
<h2>The Theme: ${esc(k.epTitle)}</h2>
<p class="theme">${esc(k.themeIntro || DEFAULT_THEME_INTRO)}</p>
<p class="question">“${esc(k.wonderingQuestion)}”</p>
<p class="theme">${esc(k.themeOutro || DEFAULT_THEME_OUTRO)}</p>
</section>

<section>
<h2>Show Details:</h2>
<ul>
  ${li('Episode', k.epNum)}
  ${li('Date', dateLong)}
  <li><b>Location:</b> Little Big Studio
    <ul>
      <li>Cloister's West Apartments</li>
      <li>1507 Kinney Ave. #109, Austin, TX</li>
      <li>We're in the second building you pass as you enter off Kinney Avenue.</li>
      <li>Park in back of that building and walk back around to the courtyard between the first set of buildings.</li>
      <li>Look for us on the ground floor with the purple light - please just walk on in - no need to knock. When you get inside, make your way to the green room for some snacks before sound check!</li>
    </ul>
  </li>
  ${musicCall ? (soundCheck === musicCall
    ? `<li><b>Musical Guests Call Time and Sound Check:</b> ${esc(musicCall)}</li>`
    : `<li><b>Musical Guests Call Time:</b> ${esc(musicCall)}${soundCheck ? ', Sound Check at ' + esc(soundCheck) : ''}</li>`) : ''}
  ${li('Pod Guests Call Time', fmtTime(t.podCall))}
  ${li('Show Circle', fmtTime(t.circle), ' (we gather together in a circle before going live)')}
  ${li('Go Live on YouTube', goLive + (showEnd ? ' - ' + showEnd : ''))}
  ${li('Show Dinner', fmtTime(t.dinner), ' (we convert the studio into a sit down candlelight dinner - it’s pretty magical and we hope you’ll stay!)')}
</ul>
<p><span class="label em">Early Arrival Hospitality:</span> Need to do makeup, get dressed, or shower after you arrive? Just let us know ahead of time and plan to come early — we'll make it happen! We have make up and hair products here for you if you forget anything.</p>
</section>

<section>
<h2>What to Bring:</h2>
<ul><li>Your stories, songs, and open mind and heart!</li><li>Your authentic self.</li></ul>
</section>

<section>
<h2>What to Wear:</h2>
<ul><li>Clothes that help you feel peaceful and comfortable.</li><li>Whatever best expresses who you are.</li></ul>
</section>

<section>
<p><span class="label">Guest List for Audience:</span> ${esc(guestList)}</p>
</section>

<section>
<h2>What to Expect:</h2>
<ul><li>An intimate space to be loved, supported, and 100% your true self.</li><li>It's natural to feel nervous or excited—we all do! You're going to do great!</li></ul>
</section>

<section>
<h2>Your Support Team:</h2>
<ul><li>Head to the Green Room upon arrival! Our Green Room Host${host ? `, ${esc(host)},` : ''} will take great care of you the moment you walk in. ${k.greenRoomHostPronoun ? `${esc(k.greenRoomHostPronoun)} will have` : 'There will be'} snacks and drinks for you to enjoy before sound check. And of course, I'll be around as well if you need anything at all!</li></ul>
</section>

${k.cameraNote ? `<section>
<h2>Your Time on Camera:</h2>
<ul><li>${esc(k.cameraNote)}</li></ul>
</section>` : ''}

<section>
<p><span class="label">Share the Love!</span> You'll receive social media promotions to share if you'd like. In the meantime, invite people to watch live:</p>
<ul>
  <li><b>To Watch:</b> <a href="${esc(watchURL)}">${esc(watchLabel)}</a></li>
  ${goLive && dateLong ? `<li><b>GO LIVE Time and Date: ${esc(goLive)} CT, ${esc(dateLong)}</b></li>` : ''}
</ul>
</section>

<section>
<p><span class="label">Please Remember:</span> This show is about cultivating community by creating space for sincere human connection. We’re not here to convince anyone of anything but rather are curious about other's stories and experiences. Thank you for sharing yours!</p>
</section>

<hr>
<section class="sig">
<p>Mark and I are here for you anytime you have questions or need anything at all.</p>
<div>
<p>Peace,</p>
<div class="signature">${esc(gsFirst)}</div>
<p class="lines"><b>${esc(gs.name || '')}</b><br>Guest Services, LBV LIVE!${gs.phone ? `<br><a href="tel:${esc(String(gs.phone).replace(/[^\d+]/g, ''))}">${esc(gs.phone)}</a>` : ''}</p>
</div>
<img class="card" src="${assetBase}lbv-mark-card.png" alt="Mark Caddell, producer/host — 512.762.8511 — mark@littlebigvoices.com">
</section>
<div class="foot">LBV LIVE! Welcome Kit · Episode ${esc(k.epNum)}</div>
</div></body></html>`;
  }

  const api = { renderWelcomeKit, welcomeKitGaps, parseEpDate, fmtDateLong, fmtTime, esc };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.LBVWelcomeKit = api;
})(typeof window !== 'undefined' ? window : globalThis);
