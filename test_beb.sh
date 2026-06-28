#!/usr/bin/env bash
# BEB pre-deploy test suite.
# Usage:  bash test_beb.sh            (normal run)
#         bash test_beb.sh --break    (inject failures to verify tests catch them)
# Every test must pass before any push.

BEB="beb.html"
PASS=0; FAIL=0
BREAK_MODE="${1:-}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
pass()  { printf '  '; green "PASS: $1"; ((PASS++)); }
fail()  { printf '  '; red   "FAIL: $1"; ((FAIL++)); }

echo ""
echo "=== BEB TEST SUITE ==="
[[ "$BREAK_MODE" == "--break" ]] && echo "  *** BREAK-TEST MODE ***"
echo ""

# ──────────────────────────────────────────────────────────────
# BREAK-TEST INJECTION
# ──────────────────────────────────────────────────────────────
if [[ "$BREAK_MODE" == "--break" ]]; then
  # Inject an unescaped backtick into the systemPrompt (simulates the crash bug)
  sed -i '' 's/HOW TO VERIFY: Check every cue/HOW TO VERIFY: Check every `cue/' "$BEB"
  echo "  Injected: backtick before 'cue' on HOW TO VERIFY line"
  # Inject wrong variable name into impliesGuestChange (simulates the userMessage scope bug)
  sed -i '' 's/\.test(text) || answeringClarification/.test(userMessage) || answeringClarification/' "$BEB"
  echo "  Injected: 'userMessage' instead of 'text' in impliesGuestChange"
  # Remove normalizeGuest from primary ingestion (simulates the socials.slice bug)
  sed -i '' 's/u\.guests\.map(normalizeGuest)/u.guests/' "$BEB"
  echo "  Injected: removed normalizeGuest from primary ingestion"
  # Remove normalizeGuest from auto-correct ingestion
  sed -i '' 's/fix\.updates\.guests\.map(normalizeGuest)/fix.updates.guests/' "$BEB"
  echo "  Injected: removed normalizeGuest from auto-correct ingestion"
  # Replace normalizeGuest coercion with a no-op (simulates function that doesn't actually coerce)
  sed -i '' "s/g\.socials = Array\.isArray(g\.socials) ? g\.socials\.join(', ') : Object\.values(g\.socials)\.join(', ');/g.socials = String(g.socials);/" "$BEB"
  echo "  Injected: replaced normalizeGuest coercion with String() no-op"
  # Remove answeringClarification from processUserInput (simulates the not-defined scope bug)
  sed -i '' 's/const answeringClarification = lastBooPI.includes/const _answeringClarification_REMOVED = lastBooPI.includes/' "$BEB"
  echo "  Injected: removed answeringClarification from processUserInput (simulates ReferenceError)"
  # Revert generateCrewChecklistShareUrl to old double-encoding (simulates SMS link regression)
  sed -i '' 's/return `https:\/\/redsuncreative\.github\.io\/beb\/checklist-view\.html?d=${toBase64Url(data)}`;/return `https:\/\/redsuncreative.github.io\/beb\/checklist-view.html?d=${encodeURIComponent(JSON.stringify(data))}`;/' "$BEB"
  echo "  Injected: generateCrewChecklistShareUrl reverted to encodeURIComponent (simulates SMS double-encoding)"
  # Revert API cue apply to a raw assignment (simulates the recompute-bypass bug)
  sed -i '' 's/if (u.cues?.length > 0) setCues(u.cues);/if (u.cues?.length > 0) showData.cues = u.cues;/' "$BEB"
  echo "  Injected: API cue apply bypasses setCues (raw showData.cues = u.cues)"
  # Comment out the standby derivation inside recomputeStructuralFields (simulates stale ready/up-next)
  sed -i '' 's/      ...deriveStandby(arr, i, guests),/      \/\/ ...deriveStandby(arr, i, guests),/' "$BEB"
  echo "  Injected: removed deriveStandby from recomputeStructuralFields"
  # Disable the performer-via-song lookup in featuredPerson (simulates missing ready cues)
  sed -i '' 's/    if (bySong) return bySong.name;/    if (false \&\& bySong) return bySong.name;/' "$BEB"
  echo "  Injected: disabled song-lookup in featuredPerson"
  echo ""
fi

# ──────────────────────────────────────────────────────────────
# TEST 1: Extract inline JS and syntax-check it
# ──────────────────────────────────────────────────────────────
echo "--- Test 1: JS syntax (node --check) ---"
python3 - > /tmp/beb_check_extract.txt 2>&1 <<'PYEOF'
from html.parser import HTMLParser
import sys

class SE(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_s = False; self.scripts = []; self.cur = []
    def handle_starttag(self, tag, attrs):
        if tag == 'script' and not dict(attrs).get('src'):
            self.in_s = True; self.cur = []
    def handle_endtag(self, tag):
        if tag == 'script' and self.in_s:
            self.scripts.append(''.join(self.cur)); self.in_s = False
    def handle_data(self, d):
        if self.in_s: self.cur.append(d)

with open('beb.html') as f:
    p = SE(); p.feed(f.read())

if not p.scripts:
    print("ERROR: no inline script found"); sys.exit(1)
with open('/tmp/beb_script_check.js', 'w') as f:
    f.write(p.scripts[0])
print(len(p.scripts[0]))
PYEOF

EXTRACT_CHARS=$(cat /tmp/beb_check_extract.txt)
if [[ "$EXTRACT_CHARS" -gt 10000 ]] 2>/dev/null; then
  pass "Script extracted ($EXTRACT_CHARS chars)"
else
  fail "Script extraction failed: $EXTRACT_CHARS"
fi

NODE_ERR=$(node --check /tmp/beb_script_check.js 2>&1)
if [[ -z "$NODE_ERR" ]]; then
  pass "No JS syntax errors"
else
  fail "JS syntax error: $NODE_ERR"
fi

# ──────────────────────────────────────────────────────────────
# TEST 2: No raw backticks inside systemPrompt template literal
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 2: No backticks inside systemPrompt ---"
python3 - > /tmp/beb_bt.txt 2>&1 <<'PYEOF'
import sys
BT = chr(96)  # backtick

with open('beb.html') as f:
    lines = f.readlines()

# Locate systemPrompt template literal bounds
start = end = None
for i, l in enumerate(lines):
    stripped = l.strip()
    if stripped.startswith('const systemPrompt') and '=' in stripped and BT in stripped:
        start = i
    if start is not None and i > start and stripped.endswith(BT + ';'):
        end = i
        break

if start is None or end is None:
    print(f"ERROR: could not locate systemPrompt (start={start}, end={end})")
    sys.exit(1)

bad = []
for i in range(start + 1, end):
    if BT in lines[i]:
        bad.append(f"line {i+1}: {lines[i].rstrip()[:100]}")

if bad:
    for b in bad:
        print(f"BACKTICK: {b}")
else:
    print("OK")
PYEOF

BT_RESULT=$(cat /tmp/beb_bt.txt)
if [[ "$BT_RESULT" == "OK" ]]; then
  pass "No raw backticks inside systemPrompt template literal"
else
  while IFS= read -r line; do
    fail "$line"
  done < /tmp/beb_bt.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 3: Required system prompt sections present
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 3: Required system prompt sections ---"
REQUIRED=(
  "SCENE REFERENCE VALIDATION"
  "RESPOND WITH JSON"
  "CRITICAL — CUE CHANGES"
  "STANDBY RULES"
  "RUNTIME"
  "THE SHOW BLUEPRINT"
  "When asking a clarifying question"
  "MANDATORY"
  "GUEST TYPE"
  "Pod guest or performance guest"
)
for section in "${REQUIRED[@]}"; do
  if grep -qF "$section" "$BEB"; then
    pass "Present: $section"
  else
    fail "MISSING: $section"
  fi
done

# ──────────────────────────────────────────────────────────────
# TEST 4: needsFullOutput routing covers key input patterns
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 4: Routing regex covers critical patterns ---"
python3 - > /tmp/beb_routing.txt 2>&1 <<'PYEOF'
import re, sys

with open('beb.html') as f:
    content = f.read()

m = re.search(r'const needsFullOutput\s*=([\s\S]*?);', content)
if not m:
    print("ERROR:needsFullOutput block not found"); sys.exit(1)

block = m.group(1)

checks = [
    (r'#\\d',         "same for #33 (scene number refs)"),
    (r'same',         "same for/as (duplicate-to-scene)"),
    (r'min',          "3 minutes (duration changes)"),
    (r'build|generate', "build/generate (cue builds)"),
    (r'add|insert|remove', "add/remove (cue mutations)"),
]

for pat, label in checks:
    if re.search(pat, block):
        print(f"OK:{label}")
    else:
        print(f"MISS:{label}")
PYEOF

while IFS= read -r line; do
  if [[ "$line" == OK:* ]];   then pass "Routing covers: ${line#OK:}";
  elif [[ "$line" == MISS:* ]]; then fail "Routing MISSING: ${line#MISS:}";
  else fail "Routing check error: $line"; fi
done < /tmp/beb_routing.txt

# ──────────────────────────────────────────────────────────────
# TEST 5: Supabase row 99 has live show data
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 5: Supabase row 99 reachable with cue data ---"
SB_OUT=$(curl -s \
  "https://gogudwpuhmidngsbqfjg.supabase.co/rest/v1/builder_state?id=eq.99&select=data" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdvZ3Vkd3B1aG1pZG5nc2JxZmpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3MTQ2NTMsImV4cCI6MjA5NDI5MDY1M30.O6n_tRQsMU29wFV_RArcN9n6gP8KSDWJQqM4P6cTq3s" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdvZ3Vkd3B1aG1pZG5nc2JxZmpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3MTQ2NTMsImV4cCI6MjA5NDI5MDY1M30.O6n_tRQsMU29wFV_RArcN9n6gP8KSDWJQqM4P6cTq3s" 2>/dev/null | \
  python3 -c "
import json,sys
rows=json.load(sys.stdin)
if not rows: print('NO_ROW'); sys.exit(1)
d=rows[0]['data']
c=len(d.get('cues',[])); g=len(d.get('guests',[]))
if c < 1: print(f'EMPTY_CUES:{c}'); sys.exit(1)
print(f'OK:{c}:{g}')
" 2>&1)

if [[ "$SB_OUT" == OK:* ]]; then
  IFS=: read _ C G <<< "$SB_OUT"
  pass "Row 99: $C cues, $G guests"
else
  fail "Supabase check failed: $SB_OUT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 6: GitHub Pages live site is serving the fixed file
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 6: GitHub Pages live site integrity ---"
BT=$(printf '`')
LIVE_FULL=$(curl -s "https://redsuncreative.github.io/beb/beb.html" -L --max-time 20 2>/dev/null)
LIVE_CHARS=${#LIVE_FULL}

if [[ "$LIVE_CHARS" -lt 50000 ]]; then
  fail "GitHub Pages: page too short or failed to fetch ($LIVE_CHARS chars)"
elif echo "$LIVE_FULL" | grep -qF "Check every ${BT}cue"; then
  fail "GitHub Pages: serving BROKEN version with backtick inside systemPrompt"
elif echo "$LIVE_FULL" | grep -q 'SCENE REFERENCE VALIDATION'; then
  pass "GitHub Pages: serving fixed version (SCENE REFERENCE VALIDATION section present, no crash backtick)"
else
  fail "GitHub Pages: SCENE REFERENCE VALIDATION section not found in live page"
fi

# ──────────────────────────────────────────────────────────────
# TEST 7: Variable scope — guest auto-correct uses 'text' not 'userMessage'
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 7: Variable scope in guest auto-correct ---"
python3 - > /tmp/beb_scope.txt 2>&1 <<'PYEOF'
import re, sys

with open('beb.html') as f:
    content = f.read()

# Find the impliesGuestChange line
m = re.search(r'const impliesGuestChange\s*=\s*(.+)', content)
if not m:
    print("ERROR: impliesGuestChange not found")
    sys.exit(1)

line = m.group(1)

# Must use 'text', must NOT use 'userMessage'
if 'userMessage' in line:
    print(f"FAIL: impliesGuestChange uses 'userMessage' (wrong scope): {line[:100]}")
elif 'text' not in line and 'answeringClarification' not in line:
    print(f"FAIL: impliesGuestChange doesn't reference 'text': {line[:100]}")
else:
    print("OK")
PYEOF

SCOPE_RESULT=$(cat /tmp/beb_scope.txt)
if [[ "$SCOPE_RESULT" == "OK" ]]; then
  pass "impliesGuestChange uses correct variable 'text' (not 'userMessage')"
else
  fail "$SCOPE_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 8: normalizeGuest is applied at BOTH guest ingestion points
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 8: normalizeGuest applied at both guest ingestion points ---"
python3 - > /tmp/beb_normalize.txt 2>&1 <<'PYEOF'
import re, sys

with open('beb.html') as f:
    content = f.read()

if 'function normalizeGuest(' not in content:
    print("FAIL: normalizeGuest function not found")
    sys.exit(0)

errors = []

# Primary ingestion: u.guests.map(normalizeGuest)
if not re.search(r'u\.guests\.map\(normalizeGuest\)', content):
    errors.append("FAIL: normalizeGuest not applied at primary ingestion (u.guests)")

# Auto-correct ingestion: fix.updates.guests.map(normalizeGuest)
if not re.search(r'fix\.updates\.guests\.map\(normalizeGuest\)', content):
    errors.append("FAIL: normalizeGuest not applied at auto-correct ingestion (fix.updates.guests)")

print('\n'.join(errors) if errors else "OK")
PYEOF

NORM_RESULT=$(cat /tmp/beb_normalize.txt)
if [[ "$NORM_RESULT" == "OK" ]]; then
  pass "normalizeGuest applied at both ingestion points"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_normalize.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 9: answeringClarification defined in processUserInput scope
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 9: answeringClarification defined in processUserInput ---"
python3 - > /tmp/beb_ac.txt 2>&1 <<'PYEOF'
import re, sys

with open('beb.html') as f:
    content = f.read()

# Find processUserInput function body
m = re.search(r'async function processUserInput\(text\)([\s\S]*?)(?=\nasync function |\nfunction )', content)
if not m:
    print("ERROR: processUserInput not found")
    sys.exit(1)

body = m.group(1)
if 'const answeringClarification' not in body:
    print("FAIL: answeringClarification not defined inside processUserInput")
else:
    print("OK")
PYEOF

AC_RESULT=$(cat /tmp/beb_ac.txt)
if [[ "$AC_RESULT" == "OK" ]]; then
  pass "answeringClarification defined in processUserInput scope"
else
  fail "$AC_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 10: normalizeGuest actually coerces non-string fields
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 10: normalizeGuest coerces object/array socials to string ---"
python3 - > /tmp/beb_normfn.txt 2>&1 <<'PYEOF'
import re, sys, json

with open('beb.html') as f:
    content = f.read()

# Extract normalizeGuest function body
m = re.search(r'function normalizeGuest\(g\)\s*\{([\s\S]*?)\n\}', content)
if not m:
    print("FAIL: normalizeGuest function body not found")
    sys.exit(0)

body = m.group(1)

# Must handle Array.isArray branch for socials
if 'Array.isArray' not in body:
    print("FAIL: normalizeGuest missing Array.isArray branch for socials coercion")
    sys.exit(0)

# Must handle object branch (Object.values or similar)
if 'Object.values' not in body and 'Object.keys' not in body and 'JSON.stringify' not in body:
    print("FAIL: normalizeGuest missing object coercion branch for socials")
    sys.exit(0)

# Must handle bio coercion
if 'g.bio' not in body:
    print("FAIL: normalizeGuest missing bio coercion")
    sys.exit(0)

print("OK")
PYEOF

NORMFN_RESULT=$(cat /tmp/beb_normfn.txt)
if [[ "$NORMFN_RESULT" == "OK" ]]; then
  pass "normalizeGuest coerces object/array socials and bio to string"
else
  fail "$NORMFN_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 11: Share URL uses base64url (no %25 double-encoding in SMS)
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 11: Share URLs use base64url — no double-encoding in SMS ---"
python3 - > /tmp/beb_shareurl.txt 2>&1 <<'PYEOF'
import re, sys, base64, json, urllib.parse

with open('beb.html') as f:
    content = f.read()

errors = []

# toBase64Url must exist
if 'function toBase64Url(' not in content:
    errors.append("FAIL: toBase64Url function not found")

# generateCrewChecklistShareUrl must use toBase64Url, not encodeURIComponent(JSON
crew_fn = re.search(r'function generateCrewChecklistShareUrl\([\s\S]*?\n\}', content)
if crew_fn:
    body = crew_fn.group(0)
    if 'toBase64Url(data)' not in body:
        errors.append("FAIL: generateCrewChecklistShareUrl does not use toBase64Url")
    if 'encodeURIComponent(JSON.stringify' in body:
        errors.append("FAIL: generateCrewChecklistShareUrl still uses encodeURIComponent(JSON.stringify)")
else:
    errors.append("FAIL: generateCrewChecklistShareUrl not found")

# generateGuestKitShareUrl must use toBase64Url
kit_fn = re.search(r'function generateGuestKitShareUrl\([\s\S]*?\n\}', content)
if kit_fn:
    body = kit_fn.group(0)
    if 'toBase64Url(data)' not in body:
        errors.append("FAIL: generateGuestKitShareUrl does not use toBase64Url")
    if 'encodeURIComponent(JSON.stringify' in body:
        errors.append("FAIL: generateGuestKitShareUrl still uses encodeURIComponent(JSON.stringify)")
else:
    errors.append("FAIL: generateGuestKitShareUrl not found")

# checklist-view.html must use fromBase64Url
try:
    with open('checklist-view.html') as f:
        cv = f.read()
    if 'fromBase64Url(' not in cv:
        errors.append("FAIL: checklist-view.html does not use fromBase64Url")
    if 'JSON.parse(decodeURIComponent(' in cv:
        errors.append("FAIL: checklist-view.html still uses old decodeURIComponent decode")
except:
    errors.append("FAIL: checklist-view.html not found")

# kit-view.html must use fromBase64Url
try:
    with open('kit-view.html') as f:
        kv = f.read()
    if 'fromBase64Url(' not in kv:
        errors.append("FAIL: kit-view.html does not use fromBase64Url")
except:
    errors.append("FAIL: kit-view.html not found")

# Simulate base64url round-trip in Python
def to_base64url(obj):
    raw = json.dumps(obj, ensure_ascii=False).encode('utf-8')
    b64 = base64.b64encode(raw).decode('ascii')
    return b64.replace('+', '-').replace('/', '_').replace('=', '')

def from_base64url(s):
    padding = '=='
    b64 = (s + padding).replace('-', '+').replace('_', '/')
    raw = base64.b64decode(b64)
    return json.loads(raw.decode('utf-8'))

test_data = {'epNum': 9, 'name': 'Sofía García', 'role': 'Floor Manager', 'callTime': '5:00 PM', 'crew': []}
encoded = to_base64url(test_data)
decoded = from_base64url(encoded)
if decoded != test_data:
    errors.append(f"FAIL: base64url round-trip mismatch: {decoded}")

# No %25 in SMS body
url = 'https://redsuncreative.github.io/beb/checklist-view.html?d=' + encoded
msg = f'Hi Sofia! Your checklist: {url}'
sms_body = urllib.parse.quote(msg, safe='')
if '%25' in sms_body:
    errors.append("FAIL: %25 double-encoding found in SMS body")

# URL length check
if len(url) > 800:
    errors.append(f"FAIL: Share URL too long ({len(url)} chars)")

print('\n'.join(errors) if errors else "OK")
PYEOF

SHARE_RESULT=$(cat /tmp/beb_shareurl.txt)
if [[ "$SHARE_RESULT" == "OK" ]]; then
  pass "Share URLs use base64url — no double-encoding in SMS body"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_shareurl.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 12: Adjacency fields re-derive after a reorder (behavioral)
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 12: standby/next re-derive after reorder ---"
python3 - > /tmp/beb_derive.js 2>/dev/null <<'PYEOF'
src = open('beb.html').read()
def extract(name):
    idx = src.find('function ' + name + '(')
    if idx < 0: return ''
    b = src.find('{', idx); depth = 0; i = b
    while i < len(src):
        if src[i] == '{': depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0: return src[idx:i+1]
        i += 1
    return ''
out = []
for fn in ('featuredPerson', 'deriveStandby', 'deriveWarnings', 'recomputeStructuralFields'):
    body = extract(fn)
    if not body:
        print('// MISSING ' + fn)
    out.append(body)
print('\n\n'.join(out))
print("const STAGE_LABEL={pod:'Pod Stage',music:'Music Stage',kitchen:'Kitchen Disco',video:'Video'};")
print('''
function assert(c, m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
const original = [
  {scene:'Opening', stageType:'pod', dur:5},
  {scene:'Kitchen Disco', stageType:'kitchen', dur:5},
  {scene:'Interview — Alice', stageType:'pod', dur:10},
  {scene:'Music Set', stageType:'music', dur:5},
  {scene:'Interview — Bob', stageType:'pod', dur:10},
];
let r = recomputeStructuralFields(original);
assert(r[1].standbyWho === 'Alice', 'kitchen standby should be Alice before reorder, got ' + r[1].standbyWho);
assert(r[3].standbyWho === 'Bob', 'music standby should be Bob before reorder, got ' + r[3].standbyWho);
// reorder -> Opening, Kitchen, Bob, Music, Alice
const re = original.slice();
const [bob] = re.splice(4,1);
const [alice] = re.splice(2,1);
re.splice(2,0,bob);
re.splice(4,0,alice);
r = recomputeStructuralFields(re);
assert(r[1].standbyWho === 'Bob', 'kitchen standby should re-derive to Bob after reorder, got ' + r[1].standbyWho);
assert(r[3].standbyWho === 'Alice', 'music standby should re-derive to Alice after reorder, got ' + r[3].standbyWho);
assert(r[1].nextScene === 'Interview — Bob', 'nextScene after kitchen should be Bob, got ' + r[1].nextScene);
console.log('OK');
''')
PYEOF

DERIVE_RESULT=$(node /tmp/beb_derive.js 2>&1)
if [[ "$DERIVE_RESULT" == *"OK"* ]] && [[ "$DERIVE_RESULT" != *"FAIL"* ]] && [[ "$DERIVE_RESULT" != *"MISSING"* ]]; then
  pass "standby/next re-derive correctly after reorder"
else
  fail "recompute behavioral test: $DERIVE_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 13: Every cue-mutation path routes through setCues()
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 13: cue mutations route through setCues() ---"
python3 - > /tmp/beb_setcues.txt 2>&1 <<'PYEOF'
import re
content = open('beb.html').read()
errors = []
if 'function setCues(' not in content:
    errors.append("FAIL: setCues() helper not found")
if 'recomputeStructuralFields' not in content.split('function setCues(')[-1][:200] if 'function setCues(' in content else True:
    pass  # depth-checked below
# setCues must recompute
m = re.search(r'function setCues\([^)]*\)\s*\{([^}]*)\}', content)
if not m or 'recomputeStructuralFields' not in m.group(1):
    errors.append("FAIL: setCues() does not call recomputeStructuralFields")
# API apply paths must use setCues, not raw assignment
if re.search(r'showData\.cues\s*=\s*u\.cues\b', content):
    errors.append("FAIL: raw 'showData.cues = u.cues' bypasses setCues (API apply)")
if re.search(r'showData\.cues\s*=\s*fix\.updates\.cues\b', content):
    errors.append("FAIL: raw 'showData.cues = fix.updates.cues' bypasses setCues (auto-correct)")
if 'setCues(u.cues)' not in content:
    errors.append("FAIL: API apply does not call setCues(u.cues)")
if 'setCues(fix.updates.cues)' not in content:
    errors.append("FAIL: auto-correct does not call setCues(fix.updates.cues)")
# Edit Show Script + FULL DETAILS saves must recompute
for fn in ('saveROSEditAll', 'saveSceneEdit'):
    mm = re.search(r'function ' + fn + r'\([^)]*\)\s*\{', content)
    if not mm:
        errors.append("FAIL: " + fn + " not found"); continue
    start = mm.start(); depth = 0; i = content.find('{', start); body_start = i
    while i < len(content):
        if content[i] == '{': depth += 1
        elif content[i] == '}':
            depth -= 1
            if depth == 0: break
        i += 1
    body = content[body_start:i]
    if 'setCues(' not in body:
        errors.append("FAIL: " + fn + " does not route through setCues()")
print('\n'.join(errors) if errors else "OK")
PYEOF

SETCUES_RESULT=$(cat /tmp/beb_setcues.txt)
if [[ "$SETCUES_RESULT" == "OK" ]]; then
  pass "all cue mutations route through setCues() (single source of truth)"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_setcues.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 14: standby falls back to booName + recompute is idempotent
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 14: booName fallback + idempotent recompute ---"
python3 - > /tmp/beb_fallback.js <<'PYEOF'
src=open('beb.html').read()
def extract(name):
    i=src.find('function '+name+'('); b=src.find('{',i); d=0; j=b
    while j<len(src):
        if src[j]=='{': d+=1
        elif src[j]=='}':
            d-=1
            if d==0: return src[i:j+1]
        j+=1
    return ''
for fn in ('featuredPerson','deriveStandby','deriveWarnings','recomputeStructuralFields'):
    print(extract(fn) or ('// MISSING '+fn)); print()
print("const STAGE_LABEL={pod:'Pod Stage',music:'Music Stage',kitchen:'Kitchen Disco',video:'Video'};")
print(r'''
function assert(c,m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
// Buffer scene whose next pod is a host-named opener (no "— Name") carrying booName.
const cues = [
  {scene:'COLD OPEN', stageType:'music', dur:5},
  {scene:'Mark SHOW OPENER', stageType:'pod', dur:5, booName:'Karly Pittman'},
  {scene:'KITCHEN DISCO', stageType:'kitchen', dur:5},
  {scene:'INTERVIEW — Kyndle Lee', stageType:'pod', dur:10},
];
const r = recomputeStructuralFields(cues);
assert(r[0].standbyWho === 'Karly Pittman', 'buffer should fall back to booName for host-named opener, got "' + r[0].standbyWho + '"');
// Idempotency: recompute(recompute(x)) === recompute(x)
const once = JSON.stringify(recomputeStructuralFields(cues));
const twice = JSON.stringify(recomputeStructuralFields(recomputeStructuralFields(cues)));
assert(once === twice, 'recompute is not idempotent');
console.log('OK');
''')
PYEOF

FALLBACK_RESULT=$(node /tmp/beb_fallback.js 2>&1)
if [[ "$FALLBACK_RESULT" == *"OK"* ]] && [[ "$FALLBACK_RESULT" != *"FAIL"* ]] && [[ "$FALLBACK_RESULT" != *"MISSING"* ]]; then
  pass "standby falls back to booName + recompute is idempotent"
else
  fail "booName-fallback/idempotency test: $FALLBACK_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 15: performer resolved via song lookup; ready cue points to next performer
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 15: performer-via-song ready cue ---"
python3 - > /tmp/beb_song.js <<'PYEOF'
src=open('beb.html').read()
def extract(name):
    i=src.find('function '+name+'('); b=src.find('{',i); d=0; j=b
    while j<len(src):
        if src[j]=='{': d+=1
        elif src[j]=='}':
            d-=1
            if d==0: return src[i:j+1]
        j+=1
    return ''
for fn in ('featuredPerson','deriveStandby','deriveWarnings','recomputeStructuralFields'):
    print(extract(fn) or ('// MISSING '+fn)); print()
print("const STAGE_LABEL={pod:'Pod Stage',music:'Music Stage',kitchen:'Kitchen Disco',video:'Video'};")
print(r'''
function assert(c,m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
const guests = [
  {name:'David Rothgeb', stageType:'music', songs:[{name:'Missing In Our Kissing'},{name:'What Can I Do'}]},
  {name:'Darren Tjepkema', stageType:'music', songs:[{name:'Poetry Reading'}]},
  {name:'Kyndle Lee', stageType:'pod', songs:[]},
];
const cues = [
  {scene:'INTERVIEW — Kyndle Lee', stageType:'pod', dur:10},
  {scene:'PERFORMANCE — Missing In Our Kissing', stageType:'music', dur:4},
  {scene:'PERFORMANCE — Poetry Reading', stageType:'music', dur:2, booName:'Kyndle Lee'},
];
// performer resolved from the song roster, NOT the scene title
assert(featuredPerson(cues[1], guests) === 'David Rothgeb', 'Missing In Our Kissing should resolve to David, got "' + featuredPerson(cues[1], guests) + '"');
assert(featuredPerson(cues[2], guests) === 'Darren Tjepkema', 'Poetry Reading should resolve to Darren (not stale booName), got "' + featuredPerson(cues[2], guests) + '"');
// the interview scene's ready cue is the NEXT performer, sent to the Music stage
const r = recomputeStructuralFields(cues, guests);
assert(r[0].standbyWho === 'David Rothgeb', 'interview ready cue should be David, got "' + r[0].standbyWho + '"');
assert(r[0].standbyStage === 'music', 'ready stage should be music, got "' + r[0].standbyStage + '"');
console.log('OK');
''')
PYEOF

SONG_RESULT=$(node /tmp/beb_song.js 2>&1)
if [[ "$SONG_RESULT" == *"OK"* ]] && [[ "$SONG_RESULT" != *"FAIL"* ]] && [[ "$SONG_RESULT" != *"MISSING"* ]]; then
  pass "performer resolved via song lookup; ready cue points to next performer"
else
  fail "performer/song ready-cue test: $SONG_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# BREAK-TEST CLEANUP
# ──────────────────────────────────────────────────────────────
if [[ "$BREAK_MODE" == "--break" ]]; then
  sed -i '' 's/HOW TO VERIFY: Check every `cue/HOW TO VERIFY: Check every cue/' "$BEB"
  sed -i '' 's/\.test(userMessage) || answeringClarification/.test(text) || answeringClarification/' "$BEB"
  sed -i '' 's/showData\.guests = u\.guests;/showData.guests = u.guests.map(normalizeGuest);/' "$BEB"
  sed -i '' 's/fix\.updates\.guests;/fix.updates.guests.map(normalizeGuest);/' "$BEB"
  sed -i '' "s/g\.socials = String(g\.socials);/g.socials = Array.isArray(g.socials) ? g.socials.join(', ') : Object.values(g.socials).join(', ');/" "$BEB"
  sed -i '' 's/const _answeringClarification_REMOVED = lastBooPI.includes/const answeringClarification = lastBooPI.includes/' "$BEB"
  sed -i '' 's/return `https:\/\/redsuncreative\.github\.io\/beb\/checklist-view\.html?d=${encodeURIComponent(JSON\.stringify(data))}`;/return `https:\/\/redsuncreative.github.io\/beb\/checklist-view.html?d=${toBase64Url(data)}`;/' "$BEB"
  sed -i '' 's/if (u.cues?.length > 0) showData.cues = u.cues;/if (u.cues?.length > 0) setCues(u.cues);/' "$BEB"
  sed -i '' 's/      \/\/ ...deriveStandby(arr, i, guests),/      ...deriveStandby(arr, i, guests),/' "$BEB"
  sed -i '' 's/    if (false \&\& bySong) return bySong.name;/    if (bySong) return bySong.name;/' "$BEB"
  echo ""
  echo "  (break-test injections removed — file restored)"
fi

# ──────────────────────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────────────────────
echo ""
echo "=============================="
printf "  "; green "PASSED: $PASS"
[[ $FAIL -gt 0 ]] && { printf "  "; red "FAILED: $FAIL"; } || true
echo "=============================="
echo ""
[[ $FAIL -eq 0 ]]
