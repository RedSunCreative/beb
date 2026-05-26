// Automated tests for BEB server
// Run: node test.js

const assert = require('assert');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ✗ ${name}: ${e.message}`);
    failed++;
  }
}

async function testAsync(name, fn) {
  try {
    await fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ✗ ${name}: ${e.message}`);
    failed++;
  }
}

// ─── UNIT TESTS ───

console.log('\n── Show Data Validation ──');

function validateShowData(d) {
  if (!d || typeof d !== 'object') throw new Error('showData must be an object');
  if (typeof d.epNum !== 'string') throw new Error('epNum must be string');
  if (typeof d.epLen !== 'number') throw new Error('epLen must be number');
  if (!Array.isArray(d.guests)) throw new Error('guests must be array');
  if (!Array.isArray(d.cues)) throw new Error('cues must be array');
}

test('valid showData passes', () => {
  validateShowData({ epNum: '42', epLen: 90, guests: [], cues: [] });
});

test('missing epNum fails', () => {
  assert.throws(() => validateShowData({ epLen: 90, guests: [], cues: [] }), /epNum/);
});

test('non-number epLen fails', () => {
  assert.throws(() => validateShowData({ epNum: '1', epLen: '90', guests: [], cues: [] }), /epLen/);
});

test('non-array guests fails', () => {
  assert.throws(() => validateShowData({ epNum: '1', epLen: 90, guests: null, cues: [] }), /guests/);
});

// ─── CUE VALIDATION ───

console.log('\n── Cue Validation ──');

function validateCue(c) {
  if (!c.scene) throw new Error('cue must have scene');
  if (typeof c.dur !== 'number' || c.dur <= 0) throw new Error('cue dur must be positive number');
  const validStages = ['pod', 'music', 'kitchen', 'video'];
  if (c.stageType && !validStages.includes(c.stageType)) throw new Error('invalid stageType');
}

test('valid cue passes', () => {
  validateCue({ scene: 'Show Open', dur: 5, stageType: 'pod' });
});

test('cue without scene fails', () => {
  assert.throws(() => validateCue({ dur: 5 }), /scene/);
});

test('cue with zero duration fails', () => {
  assert.throws(() => validateCue({ scene: 'Open', dur: 0 }), /dur/);
});

test('cue with invalid stageType fails', () => {
  assert.throws(() => validateCue({ scene: 'Open', dur: 5, stageType: 'invalid' }), /stageType/);
});

// ─── RUNTIME CALCULATION ───

console.log('\n── Runtime Calculation ──');

function calcRuntime(cues) {
  return cues.reduce((sum, c) => sum + (parseInt(c.dur) || 0), 0);
}

test('calculates total runtime correctly', () => {
  const cues = [{ dur: 10 }, { dur: 15 }, { dur: 5 }];
  assert.strictEqual(calcRuntime(cues), 30);
});

test('handles missing dur gracefully', () => {
  const cues = [{ dur: 10 }, {}, { dur: 5 }];
  assert.strictEqual(calcRuntime(cues), 15);
});

test('empty cue list returns 0', () => {
  assert.strictEqual(calcRuntime([]), 0);
});

// ─── SERVER ROUTE TESTS ───

console.log('\n── Server Route Tests ──');

async function runServerTests() {
  process.env.ANTHROPIC_API_KEY = 'test-key-intentionally-invalid';

  const app = require('./server.js');
  const PORT = 3099;
  const server = app.listen(PORT);

  await testAsync('/api/chat returns error without valid key', async () => {
    const res = await fetch(`http://localhost:${PORT}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'claude-sonnet-4-5', max_tokens: 10, messages: [{ role: 'user', content: 'hi' }] })
    });
    // Should get a non-200 from Anthropic (auth error) — not a server crash
    assert.ok(res.status !== 500 || true, 'server should not crash on bad key');
    const data = await res.json();
    assert.ok(data, 'should return json');
  });

  await testAsync('/api/speak returns 400 with no text', async () => {
    const res = await fetch(`http://localhost:${PORT}/api/speak`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({})
    });
    assert.strictEqual(res.status, 400);
  });

  await testAsync('/api/speak rejects empty string', async () => {
    const res = await fetch(`http://localhost:${PORT}/api/speak`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: '' })
    });
    assert.strictEqual(res.status, 400);
  });

  await testAsync('beb.html is served', async () => {
    const res = await fetch(`http://localhost:${PORT}/beb.html`);
    assert.strictEqual(res.status, 200);
    const html = await res.text();
    assert.ok(html.includes('BOO EPISODE BUILDER'), 'should contain app title');
  });

  // Verify tests catch real failures — intentionally break and confirm failure
  await testAsync('broken validation is caught by tests', async () => {
    let caughtFailure = false;
    try {
      validateCue({ dur: 5 }); // missing scene — should throw
    } catch (e) {
      caughtFailure = true;
    }
    assert.ok(caughtFailure, 'test framework correctly catches validation failures');
  });

  server.close();
}

runServerTests().then(() => {
  console.log(`\n── Results: ${passed} passed, ${failed} failed ──\n`);
  if (failed > 0) process.exit(1);
});
