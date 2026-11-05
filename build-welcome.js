#!/usr/bin/env node
// Builds a guest Welcome Kit from welcome-e{N}.json through the ONE template (welcome-kit.js).
//   node build-welcome.js welcome-e12.json          → beb/welcome-e12.html        (redsuncreative.github.io/beb/)
//   node build-welcome.js welcome-e12.json --guests → ../lbv-guests/e12.html     (welcome.littlebigvoices.com/e12)
// Refuses to write a kit with gaps (no blank date or call time goes to a guest).
const fs = require('fs'), path = require('path');
const { renderWelcomeKit, welcomeKitGaps } = require('./welcome-kit.js');
const GUESTS_DIR = path.join(__dirname, '..', 'lbv-guests');
const GUESTS_ASSETS = 'https://welcome.littlebigvoices.com/assets/';
const src = process.argv[2];
const guests = process.argv.includes('--guests');
if (!src) { console.error('usage: node build-welcome.js welcome-e{N}.json [--guests]'); process.exit(2); }
const kit = JSON.parse(fs.readFileSync(src, 'utf8'));
const gaps = welcomeKitGaps(kit);
if (gaps.length) { console.error('STOP — kit is missing: ' + gaps.join(', ')); process.exit(1); }
if (guests) {
  if (!fs.existsSync(GUESTS_DIR)) { console.error('STOP — no ' + GUESTS_DIR); process.exit(1); }
  const out = path.join(GUESTS_DIR, `e${kit.epNum}.html`);
  fs.writeFileSync(out, renderWelcomeKit(kit, { assetBase: GUESTS_ASSETS }));
  console.log(`wrote ${out}`);
} else {
  const out = `welcome-e${kit.epNum}.html`;
  fs.writeFileSync(out, renderWelcomeKit(kit));
  console.log(`wrote ${out}`);
}
