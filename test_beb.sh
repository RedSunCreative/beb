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
# BREAK-TEST CLEANUP
# ──────────────────────────────────────────────────────────────
if [[ "$BREAK_MODE" == "--break" ]]; then
  sed -i '' 's/HOW TO VERIFY: Check every `cue/HOW TO VERIFY: Check every cue/' "$BEB"
  sed -i '' 's/\.test(userMessage) || answeringClarification/.test(text) || answeringClarification/' "$BEB"
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
