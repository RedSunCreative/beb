#!/usr/bin/env node
// Interim builder: node build-welcome.js welcome-e12.json  →  welcome-e12.html
// Refuses to write a kit with gaps (no blank date or call time goes to a guest).
const fs = require('fs');
const { renderWelcomeKit, welcomeKitGaps } = require('./welcome-kit.js');
const src = process.argv[2];
if (!src) { console.error('usage: node build-welcome.js welcome-e{N}.json'); process.exit(2); }
const kit = JSON.parse(fs.readFileSync(src, 'utf8'));
const gaps = welcomeKitGaps(kit);
if (gaps.length) { console.error('STOP — kit is missing: ' + gaps.join(', ')); process.exit(1); }
const out = `welcome-e${kit.epNum}.html`;
fs.writeFileSync(out, renderWelcomeKit(kit));
console.log(`wrote ${out}`);
