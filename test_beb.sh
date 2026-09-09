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
  # Disable the performer-via-song lookup in autoResolveNowPerson (simulates missing ready cues)
  sed -i '' 's/    if (bySong) return bySong.name;/    if (false \&\& bySong) return bySong.name;/' "$BEB"
  echo "  Injected: disabled song-lookup in autoResolveNowPerson"
  # Neutralize the guest role default (simulates role going undefined)
  sed -i '' "s/  if (g.role == null) g.role = '';/  if (g.role == null) g.role = g.role;/" "$BEB"
  echo "  Injected: removed guest role default"
  # Neutralize the guest intro default
  sed -i '' "s/  if (g.intro == null) g.intro = '';/  if (g.intro == null) g.intro = g.intro;/" "$BEB"
  echo "  Injected: removed guest intro default"
  # Break the generic teleprompter function name (simulates missing reader)
  sed -i '' 's/function openTeleprompter(/function _brk_openTeleprompter(/' "$BEB"
  echo "  Injected: renamed openTeleprompter"
  # Break the guest About field wiring
  sed -i '' "s/,'about',this.value)/,'aboutBRK',this.value)/" "$BEB"
  echo "  Injected: broke guest About field wiring"
  # Drop a named stage from CUE_STAGES
  sed -i '' "s/label: 'Red Velvet Stage' }/label: 'RedVelvetBRK' }/" "$BEB"
  echo "  Injected: removed Red Velvet Stage from CUE_STAGES"
  # Break host-name detection in autoResolveNowPerson
  sed -i '' "s/test(cue.scene || '')) return host;/test(cue.scene || '')) return '';/" "$BEB"
  echo "  Injected: disabled host-name detection in autoResolveNowPerson"
  # Break the ADD CUE handler
  sed -i '' 's/function addCue(/function _brk_addCue(/' "$BEB"
  echo "  Injected: renamed addCue"
  # Break the DELETE SCENE handler
  sed -i '' 's/function deleteScene(/function _brk_deleteScene(/' "$BEB"
  echo "  Injected: renamed deleteScene"
  # Reintroduce the booName-into-NOW leak in resolveNowPeople (the exact class bug we fixed)
  sed -i '' 's/  return auto ? \[auto\] : \[\];/  return auto ? [auto] : (cue.booName ? [cue.booName] : []);/' "$BEB"
  echo "  Injected: resolveNowPeople falls back to booName (re-leaks NEXT into NOW)"
  # Make resolveNameToRoster silently pick the first match on an ambiguous partial name
  sed -i '' 's/if (firstMatches.length === 1) return firstMatches\[0\].name;/if (firstMatches.length >= 1) return firstMatches[0].name;/' "$BEB"
  echo "  Injected: resolveNameToRoster guesses first match on ambiguous name"
  # Float the confirm checkbox above the crew member's name (the exact layout bug we fixed)
  sed -i '' 's|// Layout order is deliberate: NAME first|// toggleCrewConfirmed( floated above NAME|' "$BEB"
  echo "  Injected: confirm checkbox marker floated above the crew name"
  # Revert the SMS href keying to the positional .crew-sms walk
  sed -i '' 's/document.querySelectorAll(.\[data-crew-sms\].)/document.querySelectorAll(".crew-sms")/' "$BEB"
  echo "  Injected: updateCrewMsg reverted to positional .crew-sms walk"
  # Revert tech import to sourcing every field from one wholesale best match (drops lighting)
  sed -i '' 's/const src = ranked.find(p =>/const src = [ranked[0]].find(p =>/' "$BEB"
  echo "  Injected: tech import takes all fields from the single best match"
  # Put LIGHTING back in the default import set (the clutter regression)
  sed -i '' "s/.filter(k => k !== 'lightingNow');/.filter(k => k !== 'nothingAtAll');/" "$BEB"
  echo "  Injected: lighting included in the default tech import set"
  # Make the lighting opt-in sticky across opens
  sed -i '' 's/  _techIncludeLighting = false;   \/\/ opt-in per open, never sticky/  \/\/ sticky-BRK/' "$BEB"
  echo "  Injected: lighting opt-in no longer resets when the dialog reopens"
  # Drop the ON NOW / HOST rows from the printed outline
  sed -i '' 's/<div class="col-notes">${nowLine}${crewLines}${booLine}${cardLine}${standbyLine}<\/div>/<div class="col-notes">${crewLines}${booLine}${standbyLine}<\/div>/' "$BEB"
  echo "  Injected: outline drops the ON NOW and HOST cue-card rows"
  # Leak the print-only host into the derived NOW data (would poison standby)
  sed -i '' "s/  if (!host || cue.prelive || (cue.stageType || '') !== 'pod') return people;/  if (!host) return people;/" "$BEB"
  echo "  Injected: host added to NOW on every scene, not just the pod table"
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
  "GUEST TYPE & ROLE"
  "Which stage — pod, performance, or Kitchen Disco"
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
for fn in ('autoResolveNowPerson', 'resolveNameToRoster', 'splitNowEntry', 'resolveNowDisplay', 'nowIdentity', 'nowIdentities', 'resolveNowPeople', 'nowLabel', 'deriveStandby', 'deriveWarnings', 'recomputeStructuralFields'):
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
for fn in ('autoResolveNowPerson','resolveNameToRoster','splitNowEntry','resolveNowDisplay','nowIdentity','nowIdentities','resolveNowPeople','nowLabel','deriveStandby','deriveWarnings','recomputeStructuralFields'):
    print(extract(fn) or ('// MISSING '+fn)); print()
print("const STAGE_LABEL={pod:'Pod Stage',music:'Music Stage',kitchen:'Kitchen Disco',video:'Video'};")
print("const CLIENT_CONFIG={hostName:'Mark'};")
print(r'''
function assert(c,m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
// Host-led pod scene "Mark SHOW OPENER" resolves to the HOST (CLIENT_CONFIG.hostName), NOT the
// booName "Next Up" tease. So NOW shows the host, and READY on the prior scene is the host.
const cues = [
  {scene:'COLD OPEN', stageType:'music', dur:5},
  {scene:'Mark SHOW OPENER', stageType:'pod', dur:5, booName:'Karly Pittman'},
  {scene:'KITCHEN DISCO', stageType:'kitchen', dur:5},
  {scene:'INTERVIEW — Kyndle Lee', stageType:'pod', dur:10},
];
assert(nowLabel(cues[1], []) === 'Mark', 'host-opener should resolve to the host, got "' + nowLabel(cues[1], []) + '"');
assert(nowLabel(cues[1], []) !== 'Karly Pittman', 'host-opener must NOT surface the booName next-up tease');
const r = recomputeStructuralFields(cues);
assert(r[0].standbyWho === 'Mark', 'READY before the opener should be the host (Mark), got "' + r[0].standbyWho + '"');
// The host LEADS a scene that names him: "MARK INTRODUCES DAVID" features Mark (introducing) —
// David is the one being brought up (UP NEXT), not who's on NOW.
assert(nowLabel({scene:'MARK INTRODUCES DAVID', stageType:'pod'}, [{name:'David Rothgeb', songs:[]}]) === 'Mark', 'host leads a scene naming him, got "' + nowLabel({scene:'MARK INTRODUCES DAVID', stageType:'pod'}, [{name:'David Rothgeb', songs:[]}]) + '"');
// NOW is never its own standby: deriveStandby skips the current featured person.
{ const _c=[{scene:'PERFORMANCE — A', stageType:'music', booName:''},{scene:'PERFORMANCE — B', stageType:'music'}];
  const _g=[{name:'Dee', stageType:'music', songs:[{name:'A'},{name:'B'}]}];
  assert(deriveStandby(_c,0,_g).standbyWho !== 'Dee', 'NOW performer must not also be their own READY cue'); }
// ...but the host still resolves when no guest is named in the title.
assert(nowLabel({scene:'Mark SHOW OPENER', stageType:'pod'}, [{name:'David Rothgeb', songs:[]}]) === 'Mark', 'host should still resolve when no guest is in the title');
// Idempotency: recompute(recompute(x)) === recompute(x)
const once = JSON.stringify(recomputeStructuralFields(cues));
const twice = JSON.stringify(recomputeStructuralFields(recomputeStructuralFields(cues)));
assert(once === twice, 'recompute is not idempotent');
// nowPeople (the authored NOW-people field) must survive the recompute pipeline that saveState runs
const np = recomputeStructuralFields([{scene:'PERFORMANCE — X', stageType:'music', nowPeople:['Ann']}], []);
assert(JSON.stringify(np[0].nowPeople) === JSON.stringify(['Ann']), 'nowPeople must survive recompute, got ' + JSON.stringify(np[0].nowPeople));
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
for fn in ('autoResolveNowPerson','resolveNameToRoster','splitNowEntry','resolveNowDisplay','nowIdentity','nowIdentities','resolveNowPeople','nowLabel','deriveStandby','deriveWarnings','recomputeStructuralFields'):
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
assert(nowLabel(cues[1], guests) === 'David Rothgeb', 'Missing In Our Kissing should resolve to David, got "' + nowLabel(cues[1], guests) + '"');
assert(nowLabel(cues[2], guests) === 'Darren Tjepkema', 'Poetry Reading should resolve to Darren (not stale booName), got "' + nowLabel(cues[2], guests) + '"');
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
# TEST 16: guest role field + special (kitchen) guest ready cue
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 16: guest role + kitchen/special ready cue ---"
python3 - > /tmp/beb_role.js <<'PYEOF'
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
for fn in ('normalizeGuest','autoResolveNowPerson','resolveNameToRoster','splitNowEntry','resolveNowDisplay','nowIdentity','nowIdentities','resolveNowPeople','nowLabel','deriveStandby','deriveWarnings','recomputeStructuralFields'):
    print(extract(fn) or ('// MISSING '+fn)); print()
print("const STAGE_LABEL={pod:'Pod Stage',music:'Music Stage',kitchen:'Kitchen Disco',video:'Video'};")
print(r'''
function assert(c,m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
// role defaults to '' and coerces non-strings
assert(normalizeGuest({}).role === '', 'role should default to empty string');
assert(normalizeGuest({role:5}).role === '5', 'non-string role should coerce to string');
assert(normalizeGuest({role:'Show Chef'}).role === 'Show Chef', 'role string should pass through');
assert(normalizeGuest({}).intro === '', 'intro should default to empty string');
assert(normalizeGuest({intro:5}).intro === '5', 'non-string intro should coerce to string');
['about','profile1','profile2'].forEach(function(k){ assert(normalizeGuest({})[k] === '', k+' should default to empty string'); });
assert(normalizeGuest({about:5}).about === '5', 'non-string about should coerce to string');
// a special guest on the kitchen stage gets a ready cue to the Kitchen Disco
const guests = [{name:'Chef Jane', stageType:'kitchen', role:'Show Chef', songs:[]}];
const cues = [
  {scene:'INTERVIEW — Kyndle Lee', stageType:'pod', dur:10},
  {scene:'KITCHEN DISCO #1', stageType:'kitchen', dur:6},
];
// No name in the title and no booName — the chef is detected purely by being the guest
// assigned to the kitchen stage.
assert(nowLabel(cues[1], guests) === 'Chef Jane', 'kitchen scene should feature its assigned kitchen guest, got "'+nowLabel(cues[1],guests)+'"');
const r = recomputeStructuralFields(cues, guests);
assert(r[0].standbyWho === 'Chef Jane', 'scene before kitchen disco should ready the chef, got "'+r[0].standbyWho+'"');
assert(r[0].standbyStage === 'kitchen', 'ready stage should be kitchen, got "'+r[0].standbyStage+'"');
assert(STAGE_LABEL['kitchen'] === 'Kitchen Disco', 'kitchen stage label');
console.log('OK');
''')
PYEOF

ROLE_RESULT=$(node /tmp/beb_role.js 2>&1)
if [[ "$ROLE_RESULT" == *"OK"* ]] && [[ "$ROLE_RESULT" != *"FAIL"* ]] && [[ "$ROLE_RESULT" != *"MISSING"* ]]; then
  pass "guest role field round-trips + special (kitchen) guest gets a ready cue"
else
  fail "role/special-guest test: $ROLE_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 17: guest intro teleprompter wiring present
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 17: guest intro + teleprompter wiring ---"
python3 - > /tmp/beb_tp.txt 2>&1 <<'PYEOF'
import re
c = open('beb.html').read()
errors = []
if 'function openTeleprompter(' not in c:
    errors.append("FAIL: generic openTeleprompter() missing")
if 'function openGuestIntro(' not in c:
    errors.append("FAIL: openGuestIntro() missing")
if "onclick=\"openGuestIntro(" not in c.replace('`','`'):
    errors.append("FAIL: guest card has no READ INTRO button wired to openGuestIntro")
if "updateGuest(${i},'intro'" not in c:
    errors.append("FAIL: guest card has no editable intro field")
for field in ('about','profile1','profile2'):
    if ("updateGuest(${i},'%s'" % field) not in c:
        errors.append("FAIL: guest card missing editable %s field" % field)
if "'https://'+g.profile1" not in c:
    errors.append("FAIL: profile links not rendered as clickable anchors")
# Boo must know the intro field
if ', intro,' not in c:
    errors.append("FAIL: guest shape in system prompt missing intro field")
if ', about,' not in c or 'profile1, profile2' not in c:
    errors.append("FAIL: guest shape in system prompt missing about/profile fields")
if 'spoken introduction Mark reads' not in c:
    errors.append("FAIL: system prompt missing guest-intro instruction")
print('\n'.join(errors) if errors else "OK")
PYEOF
TP_RESULT=$(cat /tmp/beb_tp.txt)
if [[ "$TP_RESULT" == "OK" ]]; then
  pass "guest intro field + generic teleprompter wired (form + Boo)"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_tp.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 18: cue-list stage dropdown includes the named stages
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 18: cue stage dropdown options ---"
python3 - > /tmp/beb_stages.txt 2>&1 <<'PYEOF'
c = open('beb.html').read()
errors = []
for s in ['Red Velvet Stage','Sun Set Stage','Guitar Stage','Rose Garden Stage','Hair/Make-up Stage','Crew Stage','Kitchen Disco']:
    if ("label: '%s'" % s) not in c:
        errors.append("FAIL: CUE_STAGES missing '%s'" % s)
if 'function stageOptionsHTML(' not in c:
    errors.append("FAIL: stageOptionsHTML() helper missing")
# definition + both cue dropdowns (editScene + showROSEditPanel) must reference it
if c.count('stageOptionsHTML(') < 3:
    errors.append("FAIL: cue dropdowns not wired to stageOptionsHTML (count=%d)" % c.count('stageOptionsHTML('))
# legacy pod/music/kitchen/video values must still be options (existing cues rely on them)
for v in ["value: 'pod'","value: 'music'","value: 'kitchen'","value: 'video'"]:
    if v not in c:
        errors.append("FAIL: CUE_STAGES dropped legacy %s" % v)
# "Sun Set Stage" must NOT be auto-rewritten to "Sunset" anymore
if 'replace(/Sun Set Stage' in c:
    errors.append("FAIL: loadState still rewrites 'Sun Set Stage' to 'Sunset'")
# BSM standby must map by label (not the old kitchen-disco default), and stageType must trickle to BSM
if 'STAGE_LABEL[sb.standbyStage]' not in c:
    errors.append("FAIL: generateBSM standby not mapped via STAGE_LABEL (named stages would mislabel)")
if 'stageType: ${q(c.stageType)}' not in c:
    errors.append("FAIL: cue stageType not emitted into BSM cue data")
# Cue cards must show NOW / UP NEXT names; BSM cue data must carry now/upNext
if 'NOW: ${esc(nowWho)}' not in c:
    errors.append("FAIL: cue card missing NOW name line")
if 'UP NEXT: ${esc(nextWho)}' not in c:
    errors.append("FAIL: cue card missing UP NEXT name line")
if 'now: ${q(nowLabel(c' not in c:
    errors.append("FAIL: BSM cue data missing now/upNext names")
# NOW must never be sourced from booName anywhere (the class bug we fixed)
if 'autoResolveNowPerson(c, showData.guests))}, upNext' in c:
    errors.append("FAIL: BSM now/upNext still bypasses nowLabel (should be nowLabel)")
print('\n'.join(errors) if errors else "OK")
PYEOF
STAGES_RESULT=$(cat /tmp/beb_stages.txt)
if [[ "$STAGES_RESULT" == "OK" ]]; then
  pass "cue stage dropdown includes named stages + keeps legacy values"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_stages.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 19: named stage flows through standby + warning (BSM direction)
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 19: named-stage standby + warning direction ---"
python3 - > /tmp/beb_namedstage.js <<'PYEOF'
import re
src = open('beb.html').read()
print(re.search(r'const CUE_STAGES = \[[\s\S]*?\];', src).group(0))
print(re.search(r'const STAGE_LABEL = .*?;', src).group(0))
def extract(name):
    i=src.find('function '+name+'('); b=src.find('{',i); d=0; j=b
    while j<len(src):
        if src[j]=='{': d+=1
        elif src[j]=='}':
            d-=1
            if d==0: return src[i:j+1]
        j+=1
    return ''
for fn in ('autoResolveNowPerson','resolveNameToRoster','splitNowEntry','resolveNowDisplay','nowIdentity','nowIdentities','resolveNowPeople','nowLabel','deriveStandby','deriveWarnings','recomputeStructuralFields'):
    print(extract(fn) or ('// MISSING '+fn)); print()
print(r'''
function assert(c,m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
assert(STAGE_LABEL['Sun Set Stage'] === 'Sun Set Stage', 'Sun Set Stage must map to itself (literal), got "'+STAGE_LABEL['Sun Set Stage']+'"');
assert(STAGE_LABEL['Red Velvet Stage'] === 'Red Velvet Stage', 'Red Velvet Stage label');
const guests = [{name:'Etta James', stageType:'music', songs:[], role:'Music'}];
// Etta is ON the Red Velvet scene — authored via nowPeople (partial "Etta" resolves to the full
// roster name). NOW comes from nowPeople, never booName.
const cues = [
  {scene:'OPENER', stageType:'pod', dur:5},
  {scene:'RED VELVET SET', stageType:'Red Velvet Stage', dur:8, nowPeople:['Etta'], booName:''},
];
const r = recomputeStructuralFields(cues, guests);
assert(r[0].standbyWho === 'Etta James', 'prior scene should ready Etta, got "'+r[0].standbyWho+'"');
assert(r[0].standbyStage === 'Red Velvet Stage', 'standby stage should be the named set, got "'+r[0].standbyStage+'"');
assert(/please head to the Red Velvet Stage/.test(r[0].w5), 'warning should direct to the named stage, got "'+r[0].w5+'"');
console.log('OK');
''')
PYEOF
NS_RESULT=$(node /tmp/beb_namedstage.js 2>&1)
if [[ "$NS_RESULT" == *"OK"* ]] && [[ "$NS_RESULT" != *"FAIL"* ]] && [[ "$NS_RESULT" != *"MISSING"* ]]; then
  pass "named studio stage flows through standby + warning (reaches BSM correctly)"
else
  fail "named-stage test: $NS_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 20: ADD CUE button, manual save, live runtime, ROS/BSM trickle
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 20: add-cue / manual-save / live-runtime / trickle ---"
python3 - > /tmp/beb_ui.txt 2>&1 <<'PYEOF'
c = open('beb.html').read()
errors = []
if 'function addCue(' not in c: errors.append("FAIL: addCue() missing")
if 'onclick="addCue()"' not in c: errors.append("FAIL: ADD CUE button not wired")
if 'function deleteScene(' not in c: errors.append("FAIL: deleteScene() missing")
if 'onclick="deleteScene(' not in c: errors.append("FAIL: DELETE SCENE button not wired")
if 'function updateRuntime(' not in c: errors.append("FAIL: updateRuntime() missing")
if 'updateRuntime();' not in c: errors.append("FAIL: updateRuntime not called from updateAllDisplays")
if 'dur=this.value;updateRuntime()' not in c: errors.append("FAIL: duration fields not wired to live runtime")
if 'onclick="saveState()"' not in c: errors.append("FAIL: manual SAVE button missing")
if 'SAVING' not in c: errors.append("FAIL: SAVING state missing")
# Trickle: a cue's duration must reach BSM and the ROS runtime
if 'dur: ${c.dur || 10}' not in c: errors.append("FAIL: BSM cue output missing dur (won't trickle to BSM)")
if 'parseDur(c.dur)' not in c: errors.append("FAIL: ROS/runtime not summing cue durations")
print('\n'.join(errors) if errors else "OK")
PYEOF
UI_RESULT=$(cat /tmp/beb_ui.txt)
if [[ "$UI_RESULT" == "OK" ]]; then
  pass "ADD CUE + manual SAVE + live runtime wired; duration trickles to BSM/ROS"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_ui.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 21: NOW/NEXT split — booName never surfaces as a NOW value; nowPeople resolves
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 21: NOW-people vs booName split (class-proof) ---"
python3 - > /tmp/beb_nowpeople.js <<'PYEOF'
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
for fn in ('autoResolveNowPerson','resolveNameToRoster','splitNowEntry','resolveNowDisplay','nowIdentity','nowIdentities','resolveNowPeople','nowLabel','deriveStandby','deriveWarnings','recomputeStructuralFields'):
    print(extract(fn) or ('// MISSING '+fn)); print()
print("const STAGE_LABEL={pod:'Pod Stage',music:'Music Stage',kitchen:'Kitchen Disco',video:'Video'};")
print("const CLIENT_CONFIG={hostName:'Mark'};")
print(r'''
function assert(c,m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
const guests = [{name:'David Rothgeb', stageType:'music', songs:[{name:'Water from the Well'}]},
                {name:'Kyndle Lee', stageType:'pod', songs:[]}];
// (a) A non-pod scene whose ONLY person reference is booName must NOT surface booName as NOW.
const countdown = {scene:'PRE-SHOW COUNTDOWN VIDEO', stageType:'video', booName:'David Rothgeb', nowPeople:[]};
assert(nowLabel(countdown, guests) === '', 'countdown NOW must be empty, not the booName tease, got "' + nowLabel(countdown, guests) + '"');
assert(resolveNowPeople(countdown, guests).length === 0, 'countdown should resolve to nobody on NOW');
// (b) Authored partial name resolves to the full roster name.
const perf = {scene:'PERFORMANCE — Water from the Well', stageType:'music', nowPeople:['David'], booName:''};
assert(nowLabel(perf, guests) === 'David Rothgeb', 'authored "David" should resolve to full name, got "' + nowLabel(perf, guests) + '"');
// (c) Ambiguous partial is NOT silently guessed — left verbatim (Boo asks before storing).
const two = [{name:'David Rothgeb'},{name:'David Kim'}];
assert(resolveNameToRoster('David', two) === 'David', 'ambiguous "David" must stay verbatim, got "' + resolveNameToRoster('David', two) + '"');
// (d) Exact full name resolves case-insensitively.
assert(resolveNameToRoster('david rothgeb', guests) === 'David Rothgeb', 'exact name (ci) should resolve');
// (e) Empty-state safety: no guests, bare cue — no throw, NOW empty.
assert(nowLabel({scene:'X'}, []) === '', 'bare cue NOW should be empty');
// (f) booName does not leak into the standby chain either: standby = next scene's NOW-person.
const cues = [countdown, {scene:'INTERVIEW — Kyndle Lee', stageType:'pod', nowPeople:['Kyndle Lee']}];
const r = recomputeStructuralFields(cues, guests);
assert(r[0].standbyWho === 'Kyndle Lee', 'standby should be next NOW-person (Kyndle), not booName, got "' + r[0].standbyWho + '"');
assert(r[0].standbyWho !== 'David Rothgeb', 'standby must NOT pick up the countdown booName tease');
console.log('OK');
''')
PYEOF
NP_RESULT=$(node /tmp/beb_nowpeople.js 2>&1)
if [[ "$NP_RESULT" == *"OK"* ]] && [[ "$NP_RESULT" != *"FAIL"* ]] && [[ "$NP_RESULT" != *"MISSING"* ]]; then
  pass "NOW resolves from nowPeople/scene; booName never surfaces as a NOW value"
else
  fail "NOW/NEXT split test: $NP_RESULT"
fi

# ──────────────────────────────────────────────────────────────
# TEST 22: BSM reads the `now` key (ON NOW, 3 views) + UP NEXT reads the live next person
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 22: BSM NOW/UP-NEXT wiring (emit reaches display) ---"
python3 - > /tmp/beb_bsmwire.txt 2>&1 <<'PYEOF'
errs=[]
b=open('beb.html').read()
t=open('bsm-template.html').read()
# BeB still emits `now`, kept `nextScene`, and dropped the dead/redundant keys
if 'now: ${q(nowLabel(c' not in b: errs.append("FAIL: generateBSM no longer emits `now`")
if 'nextScene: ${q(nxt?.scene' not in b: errs.append("FAIL: `nextScene` emit dropped (BSM reads it for ALL CLEAR)")
if 'upNext: ${q(nxt' in b: errs.append("FAIL: dead `upNext` emit still present")
if 'stageLabel: ${q(STAGE_LABEL' in b: errs.append("FAIL: dead `stageLabel` emit still present")
if 'next: ${q(nxt?.booName' in b: errs.append("FAIL: dead `next` emit still present")
# BSM displays the `now` key as ON NOW across all three views
if 'function setNowPeople(' not in t: errs.append("FAIL: setNowPeople() missing in BSM")
if 'setNowPeople(c.now)' not in t: errs.append("FAIL: render() does not set ON NOW from c.now")
for eid in ('tv-now-people','tech-now-people','host-now-people'):
    if eid not in t: errs.append("FAIL: missing ON NOW element "+eid)
# UP NEXT sourced from the LIVE next cue's now (recomputes on reorder), not a frozen key
if 'nextData.cue.now||nextData.cue.scene' not in t: errs.append("FAIL: up-next (hint/box) not sourced from live nextData.cue.now")
if 'nc.now||nc.scene' not in t: errs.append("FAIL: tech up-next not sourced from live nc.now")
print("\n".join(errs) if errs else "OK")
PYEOF
BSMWIRE=$(cat /tmp/beb_bsmwire.txt)
if [[ "$BSMWIRE" == "OK" ]]; then
  pass "BSM ON NOW reads \`now\` (3 views); UP NEXT reads live next person; dead emits dropped"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_bsmwire.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 23: crew row layout order — every checkbox has a visible subject above it
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 23: crew row layout order + index-keyed hooks ---"
python3 - > /tmp/beb_crewlayout.txt <<'PYEOF'
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
errs=[]
body=extract('renderCrewList')
if not body:
    errs.append("FAIL: renderCrewList() missing")
else:
    # The row must read top-to-bottom: name, role, confirm, checklist, email, call time,
    # mobile, send actions. A checkbox rendered above the name has no visible subject.
    ORDER=[('name input','data-crew-name='),
           ('role input','placeholder="Role"'),
           ('confirmed checkbox','toggleCrewConfirmed('),
           ('checklist checkbox','toggleCrewChecklist('),
           ('email field','placeholder="Email"'),
           ('call time field','placeholder="Call time"'),
           ('mobile field','placeholder="Mobile"'),
           ('send actions','crew-actions')]
    pos=[]
    for label,marker in ORDER:
        k=body.find(marker)
        if k<0: errs.append("FAIL: crew row is missing the "+label+" ("+marker+")")
        pos.append((label,k))
    if all(k>=0 for _,k in pos):
        for a,b2 in zip(pos,pos[1:]):
            if a[1]>=b2[1]:
                errs.append("FAIL: crew row order wrong — "+a[0]+" must render above "+b2[0])
# Index-keyed hooks: DOM-position walks silently target the wrong crew member.
um=extract('updateCrewMsg')
if um and '[data-crew-sms]' not in um:
    errs.append("FAIL: updateCrewMsg does not key SMS hrefs off data-crew-sms (positional .crew-sms walk)")
if um and 'forEach((a, i)' in um:
    errs.append("FAIL: updateCrewMsg still walks .crew-sms by DOM index")
ac=extract('addCrewMember')
if ac and 'data-crew-name' not in ac:
    errs.append("FAIL: addCrewMember does not focus the new row via data-crew-name")
if ac and 'inputs.length - 3' in ac:
    errs.append("FAIL: addCrewMember still uses the inputs[length-3] positional focus walk")
print("\n".join(errs) if errs else "OK")
PYEOF
CREWLAYOUT=$(cat /tmp/beb_crewlayout.txt)
if [[ "$CREWLAYOUT" == "OK" ]]; then
  pass "crew row renders name -> confirm -> checklist -> contact; hooks keyed by index"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_crewlayout.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 24: tech-cue import sources each field independently (lighting falls back)
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 24: tech import per-field fallback across episodes ---"
python3 - > /tmp/beb_techmatch.js <<'PYEOF'
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
i=src.find('const TECH_FIELDS = ['); print(src[i:src.find('];',i)+2] if i>=0 else '// MISSING TECH_FIELDS')
for fn in ('sceneKind','_sceneTokens','matchTechForCue'):
    print(extract(fn) or ('// MISSING '+fn)); print()
print(r'''
function assert(c,m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
// Mirrors production reality: E10 recorded no lighting on music scenes, E9 did.
const past = [
  { scene:'MUSIC — Yumm Vibration', kind:'music', epLabel:'E10',
    tech:{ camerasNow:'C2 wide on music stage', videoNow:'MUSIC LOWER THIRD', audioNow:'Music bus up', lightingNow:'' } },
  { scene:'PERFORMANCE — Water from the Well', kind:'music', epLabel:'E9',
    tech:{ camerasNow:'C1 tight', videoNow:'E9 L3', audioNow:'E9 music bus', lightingNow:'Warm amber wash, house at 30%' } },
  { scene:'POD INTERVIEW — Kenneth Spivey', kind:'interview', epLabel:'E10',
    tech:{ camerasNow:'C3 two-shot', videoNow:'', audioNow:'Pod mics 1-4', lightingNow:'' } },
];
const byKey = r => Object.fromEntries(r.fills.map(f => [f.key, f]));
const ALL = ['camerasNow','videoNow','audioNow','lightingNow'];

// (a) Newest episode wins the fields it HAS.
const music = { scene:'MUSIC — Something New', stageType:'music' };
let r = matchTechForCue(music, past);
assert(r.status === 'ready', 'music scene should be ready, got ' + r.status);
let f = byKey(r);
assert(f.camerasNow.srcEp === 'E10', 'cameras should come from E10, got ' + f.camerasNow.srcEp);
assert(f.audioNow.srcEp === 'E10', 'audio should come from E10, got ' + f.audioNow.srcEp);

// (b) LIGHTING IS EXCLUDED BY DEFAULT. On this show lighting is set once before doors,
// so an empty lighting field is deliberate — importing it puts noise on the lighting card.
assert(!f.lightingNow, 'lighting must NOT be imported by default');

// (c) Opting in turns it back on, and it still falls back to the older episode that has it.
f = byKey(matchTechForCue(music, past, { fields: ALL }));
assert(f.lightingNow, 'with fields=ALL, lighting should be offered');
assert(f.lightingNow.srcEp === 'E9', 'lighting should fall back to E9, got ' + f.lightingNow.srcEp);
assert(f.lightingNow.text === 'Warm amber wash, house at 30%', 'lighting text should come from the E9 scene');
assert(byKey(matchTechForCue(music, past, { fields: ALL })).camerasNow.srcEp === 'E10',
       'opting into lighting must not change where cameras come from');

// (d) A scene whose ONLY empty field is lighting is 'filled' by default, 'ready' when opted in.
const onlyLightingEmpty = { scene:'MUSIC — X', stageType:'music', camerasNow:'a', videoNow:'b', audioNow:'c' };
assert(matchTechForCue(onlyLightingEmpty, past).status === 'filled',
       'lighting-only gap should report filled when lighting is excluded');
assert(matchTechForCue(onlyLightingEmpty, past, { fields: ALL }).status === 'ready',
       'lighting-only gap should be ready once lighting is opted in');

// (e) Fill-empty-only: an author-written field is never offered for overwrite.
const partly = { scene:'MUSIC — Something New', stageType:'music', audioNow:'MY OWN AUDIO CUE' };
r = matchTechForCue(partly, past);
assert(!byKey(r).audioNow, 'a field the host already wrote must not be offered for fill');
assert(byKey(r).camerasNow, 'other empty fields should still fill');

// (f) All fields already written -> nothing to do.
const full = { scene:'MUSIC — X', stageType:'music', camerasNow:'a', videoNow:'b', audioNow:'c', lightingNow:'d' };
assert(matchTechForCue(full, past, { fields: ALL }).status === 'filled', 'fully-authored scene should report filled');

// (g) No same-kind past scene -> nomatch, and nothing invented.
const kitchen = { scene:'KITCHEN DISCO #1', stageType:'kitchen' };
r = matchTechForCue(kitchen, past, { fields: ALL });
assert(r.status === 'nomatch', 'kitchen has no same-kind candidate, got ' + r.status);
assert(r.fills.length === 0, 'nomatch must fill nothing');

// (h) A kind whose only candidate lacks a field leaves that field alone (no cross-kind bleed).
const interview = { scene:'POD INTERVIEW — Someone', stageType:'pod' };
f = byKey(matchTechForCue(interview, past, { fields: ALL }));
assert(f.camerasNow.srcEp === 'E10', 'interview cameras from E10');
assert(!f.videoNow, 'interview video must stay empty — no interview candidate has it');
assert(!f.lightingNow, 'interview lighting must NOT bleed in from a music scene');
console.log('OK');
''')
PYEOF
TM_RESULT=$(node /tmp/beb_techmatch.js 2>&1)
if [[ "$TM_RESULT" == *"OK"* ]] && [[ "$TM_RESULT" != *"FAIL"* ]] && [[ "$TM_RESULT" != *"MISSING"* ]]; then
  pass "tech import: per-field sourcing; lighting opt-in (off by default)"
else
  fail "tech import per-field test: $TM_RESULT"
fi

# The opt-in has to be reachable and non-sticky, or the default is meaningless.
python3 - > /tmp/beb_lightui.txt <<'PYEOF'
src=open('beb.html').read()
errs=[]
if 'id="tech-imp-lighting"' not in src: errs.append("FAIL: no LIGHTING opt-in checkbox in the tech import preview")
if 'toggleTechLighting(this.checked)' not in src: errs.append("FAIL: LIGHTING checkbox not wired to toggleTechLighting")
if 'function toggleTechLighting(' not in src: errs.append("FAIL: toggleTechLighting() missing")
if 'function recomputeTechMatches(' not in src: errs.append("FAIL: recomputeTechMatches() missing")
if '_techIncludeLighting = false;   // opt-in per open, never sticky' not in src:
    errs.append("FAIL: lighting opt-in is not reset to OFF each time the dialog opens")
if 'function captureTechChecks(' not in src: errs.append("FAIL: captureTechChecks() missing — toggling would re-arm unticked scenes")
if '_techUnchecked.has(m.i)' not in src: errs.append("FAIL: render does not honour per-scene unticks across a re-render")
print("\n".join(errs) if errs else "OK")
PYEOF
LIGHTUI=$(cat /tmp/beb_lightui.txt)
if [[ "$LIGHTUI" == "OK" ]]; then
  pass "LIGHTING opt-in is wired, defaults off per open, and preserves per-scene unticks"
else
  while IFS= read -r line; do fail "$line"; done < /tmp/beb_lightui.txt
fi

# ──────────────────────────────────────────────────────────────
# TEST 25: printed outline shows WHO IS ON (incl. the host at the pod table) + HOST card
# ──────────────────────────────────────────────────────────────
echo ""
echo "--- Test 25: printed outline ON NOW + HOST cue card ---"
python3 - > /tmp/beb_ros.js <<'PYEOF'
src=open('beb.html').read()
def const_block(name):
    i=src.find('const '+name)
    if i<0: return '// MISSING '+name
    eq=src.find('=',i); k=eq+1
    while src[k] in ' \n\t': k+=1
    if src[k] not in '[{': return src[i:src.find('\n',i)]
    op,cl=src[k],(']' if src[k]=='[' else '}'); d=0; j=k
    while j<len(src):
        if src[j]==op: d+=1
        elif src[j]==cl:
            d-=1
            if d==0: return src[i:j+1]+';'
        j+=1
def extract(name):
    i=src.find('function '+name+'(')
    if i<0: return '// MISSING '+name
    b=src.find('{',i); d=0; j=b
    while j<len(src):
        if src[j]=='{': d+=1
        elif src[j]=='}':
            d-=1
            if d==0: return src[i:j+1]
        j+=1
for c in ('parseDur','CUE_STAGES','STAGE_LABEL','CLIENT_CONFIG'): print(const_block(c))
for fn in ('sceneKind','_sceneTokens','resolveNameToRoster','splitNowEntry','resolveNowDisplay',
           'autoResolveNowPerson','resolveNowPeople','nowIdentities','nowIdentity','nowLabel',
           'onNowForPrint','deriveStandby','deriveWarnings','recomputeStructuralFields','buildROSHtml'):
    print(extract(fn)); print()
print(r'''
function assert(c,m){ if(!c){ console.log('FAIL: '+m); process.exit(0); } }
const HOST = CLIENT_CONFIG.hostName;
assert(HOST, 'CLIENT_CONFIG.hostName must be set');
const guests = [
  { name:'Soyinka Rahim', stageType:'pod', songs:[] },
  { name:'Shanik Hughes', stageType:'music', songs:[{name:'Agua a Tierra'}] },
];

// (a) Host is added at the pod table even when nowPeople never names him.
let p = onNowForPrint({ scene:'SHOW CLOSE', stageType:'pod', nowPeople:[] }, guests);
assert(p[0] === HOST, 'pod scene with no people should lead with the host, got ' + JSON.stringify(p));

// (b) Host joins an existing pod guest rather than replacing them.
p = onNowForPrint({ scene:'POD INTERVIEW — Soyinka Rahim', stageType:'pod', nowPeople:['Soyinka Rahim'] }, guests);
assert(p.length === 2 && p[0] === HOST && p[1] === 'Soyinka Rahim',
       'pod interview should read host + guest, got ' + JSON.stringify(p));

// (c) Never doubled when he is already named.
p = onNowForPrint({ scene:'SHOW OPENER', stageType:'pod', nowPeople:[HOST, 'Shanik Hughes'] }, guests);
assert(p.filter(x => x === HOST).length === 1, 'host must not be duplicated, got ' + JSON.stringify(p));

// (d) NOT added off the pod table — music, kitchen, video, or pre-show.
for (const st of ['music','kitchen','video']) {
  p = onNowForPrint({ scene:'X', stageType:st, nowPeople:[] }, guests);
  assert(!p.includes(HOST), 'host must not appear on a ' + st + ' scene');
}
p = onNowForPrint({ scene:'COUNTDOWN', stageType:'pod', prelive:true, nowPeople:[] }, guests);
assert(!p.includes(HOST), 'host must not appear on a pre-show scene');

// (e) CLASS-PROOF: the print-only host must NOT leak into the derived data, or every
// pod scene would emit a "GET READY <host>" on the scene before it.
const cues = [
  { scene:'VIDEO — roll', stageType:'video', nowPeople:[] },
  { scene:'POD INTERVIEW — Soyinka Rahim', stageType:'pod', nowPeople:['Soyinka Rahim'] },
];
assert(!resolveNowPeople(cues[1], guests).includes(HOST), 'resolveNowPeople must stay host-free');
assert(!nowIdentities(cues[1], guests).includes(HOST), 'nowIdentities must stay host-free');
const r = recomputeStructuralFields(cues, guests);
assert(r[0].standbyWho !== HOST, 'standby must not become the host, got ' + r[0].standbyWho);
assert(r[0].standbyWho === 'Soyinka Rahim', 'standby should still be the real next person, got ' + r[0].standbyWho);

// (f) The builder actually emits both new rows.
globalThis.showData = { epNum:'11', epTitle:'T', epDate:'9-17-2026', guests, cues:[
  { scene:'SHOW CLOSE', stageType:'pod', dur:3, nowPeople:[], camerasNow:'CAM 4', cueCard:'• Close the show\n• Thank crew' },
]};
const html = buildROSHtml();
assert(html.indexOf('ON NOW') >= 0, 'outline must print an ON NOW row');
assert(html.indexOf('>' + HOST + '<') >= 0 || html.indexOf(HOST) >= 0, 'outline must name the host on the close');
assert(html.indexOf('HOST') >= 0, 'outline must print a HOST cue-card row');
assert(html.indexOf('Thank crew') >= 0, 'cue card body must reach the page');
assert(html.indexOf('• Close the show<br>• Thank crew') >= 0, 'cue card newlines should become <br>');
console.log('OK');
''')
PYEOF
ROS_RESULT=$(node /tmp/beb_ros.js 2>&1)
if [[ "$ROS_RESULT" == *"OK"* ]] && [[ "$ROS_RESULT" != *"FAIL"* ]] && [[ "$ROS_RESULT" != *"MISSING"* ]]; then
  pass "outline prints ON NOW (host at pod table) + HOST cue card; derived data stays host-free"
else
  fail "printed outline test: $ROS_RESULT"
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
  sed -i '' "s/  if (g.role == null) g.role = g.role;/  if (g.role == null) g.role = '';/" "$BEB"
  sed -i '' "s/  if (g.intro == null) g.intro = g.intro;/  if (g.intro == null) g.intro = '';/" "$BEB"
  sed -i '' 's/function _brk_openTeleprompter(/function openTeleprompter(/' "$BEB"
  sed -i '' "s/,'aboutBRK',this.value)/,'about',this.value)/" "$BEB"
  sed -i '' "s/label: 'RedVelvetBRK' }/label: 'Red Velvet Stage' }/" "$BEB"
  sed -i '' "s/test(cue.scene || '')) return '';/test(cue.scene || '')) return host;/" "$BEB"
  sed -i '' 's/function _brk_addCue(/function addCue(/' "$BEB"
  sed -i '' 's/function _brk_deleteScene(/function deleteScene(/' "$BEB"
  sed -i '' 's/  return auto ? \[auto\] : (cue.booName ? \[cue.booName\] : \[\]);/  return auto ? [auto] : [];/' "$BEB"
  sed -i '' 's/if (firstMatches.length >= 1) return firstMatches\[0\].name;/if (firstMatches.length === 1) return firstMatches[0].name;/' "$BEB"
  sed -i '' 's|// toggleCrewConfirmed( floated above NAME|// Layout order is deliberate: NAME first|' "$BEB"
  sed -i '' 's/document.querySelectorAll(".crew-sms")/document.querySelectorAll('"'"'[data-crew-sms]'"'"')/' "$BEB"
  sed -i '' 's/const src = \[ranked\[0\]\].find(p =>/const src = ranked.find(p =>/' "$BEB"
  sed -i '' "s/.filter(k => k !== 'nothingAtAll');/.filter(k => k !== 'lightingNow');/" "$BEB"
  sed -i '' 's/  \/\/ sticky-BRK/  _techIncludeLighting = false;   \/\/ opt-in per open, never sticky/' "$BEB"
  sed -i '' 's/<div class="col-notes">${crewLines}${booLine}${standbyLine}<\/div>/<div class="col-notes">${nowLine}${crewLines}${booLine}${cardLine}${standbyLine}<\/div>/' "$BEB"
  sed -i '' "s/  if (!host) return people;/  if (!host || cue.prelive || (cue.stageType || '') !== 'pod') return people;/" "$BEB"
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
