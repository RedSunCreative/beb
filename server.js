// Boo ADB Server — pushes URLs to Fire TVs over WiFi
// Run with: npm run adb-server
// Requires: adb installed (brew install android-platform-tools)
// Each Fire TV needs: Developer Options → ADB Debugging ON + Network Debugging ON

const http = require('http');
const { exec } = require('child_process');

const PORT = 3001;

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function json(res, code, data) {
  cors(res);
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function run(cmd) {
  return new Promise((resolve) => {
    exec(cmd, { timeout: 10000 }, (err, stdout, stderr) => {
      resolve({ ok: !err, stdout: stdout?.trim(), stderr: stderr?.trim(), error: err?.message });
    });
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { cors(res); res.writeHead(204); res.end(); return; }

  if (req.method === 'POST' && req.url === '/adb/open-url') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', async () => {
      let ip, url;
      try { ({ ip, url } = JSON.parse(body)); } catch(e) {
        return json(res, 400, { ok: false, error: 'Invalid JSON' });
      }
      if (!ip || !url) return json(res, 400, { ok: false, error: 'Missing ip or url' });

      // Connect to device
      const connect = await run(`adb connect ${ip}:5555`);
      if (!connect.ok && !connect.stdout?.includes('connected')) {
        return json(res, 200, { ok: false, error: `Couldn't reach ${ip} — is it on the same network with ADB enabled?`, detail: connect.stderr });
      }

      // Open URL in Silk
      const open = await run(`adb -s ${ip}:5555 shell am start -a android.intent.action.VIEW -d "${url}" com.amazon.silk`);
      return json(res, 200, { ok: open.ok, stdout: open.stdout, error: open.error });
    });
    return;
  }

  if (req.method === 'GET' && req.url === '/ping') {
    return json(res, 200, { ok: true, version: '1.0' });
  }

  res.writeHead(404); res.end();
});

server.listen(PORT, () => {
  console.log(`\n  Boo ADB Server  →  http://localhost:${PORT}`);
  console.log('  Fire TV push ready. Keep this running while in the studio.\n');
  console.log('  Setup checklist:');
  console.log('  ✓ brew install android-platform-tools');
  console.log('  ✓ Fire TV: Settings → My Fire TV → Developer Options → ADB Debugging ON');
  console.log('  ✓ Fire TV: Settings → My Fire TV → Developer Options → Network Debugging ON\n');
});
