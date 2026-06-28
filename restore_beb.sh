#!/usr/bin/env bash
# restore_beb.sh — restore a BEB Supabase row from a backup JSON file.
#
# Safety model (matches Mark's standing rule):
#   1. Validates the backup file actually has cue data (refuses empty/garbage).
#   2. Takes a FRESH pre-restore backup of the TARGET row first — so the restore
#      itself is reversible. Path is printed so you can undo by re-restoring it.
#   3. Restores via REST PATCH of {data, history} (verified to work with the anon key).
#   4. Re-reads the row and VERIFIES it now matches the file (cue/guest counts + data hash).
#      Exits non-zero and shouts if the verification fails.
#
# Usage:
#   bash restore_beb.sh <backup-file.json> [row]        # prompts before writing
#   bash restore_beb.sh <backup-file.json> [row] --yes  # no prompt (scripted)
#
# Examples:
#   bash restore_beb.sh backups/builder_state-row99-2026-06-28_005808.json        # -> row 99
#   bash restore_beb.sh ~/Library/Application\ Support/boo-suite/backups/foo.json 99

set -euo pipefail

FILE="${1:-}"
ROW="${2:-99}"
YES="${3:-}"
[[ "$ROW" == "--yes" ]] && { YES="--yes"; ROW=99; }

SB_URL="https://gogudwpuhmidngsbqfjg.supabase.co"
KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdvZ3Vkd3B1aG1pZG5nc2JxZmpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3MTQ2NTMsImV4cCI6MjA5NDI5MDY1M30.O6n_tRQsMU29wFV_RArcN9n6gP8KSDWJQqM4P6cTq3s"
DIR="$(cd "$(dirname "$0")" && pwd)/backups"
mkdir -p "$DIR"
TS="$(date +%Y-%m-%d_%H%M%S)"

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "ERROR: backup file not found: '$FILE'" >&2; exit 1
fi

# 1) Validate the file has real cue data, and capture what we're about to restore.
SUMMARY=$(python3 - "$FILE" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
if not isinstance(rows, list) or not rows or not rows[0].get('data'):
    print("BAD: file has no row/data"); sys.exit(0)
d = rows[0]['data']
cues = d.get('cues') or []
if len(cues) < 1:
    print("BAD: file has 0 cues"); sys.exit(0)
print(f"OK {len(cues)} {len(d.get('guests') or [])} {len(d.get('crew') or [])} E{d.get('epNum')}")
PY
)
if [[ "$SUMMARY" != OK* ]]; then
  echo "ERROR: refusing to restore — $SUMMARY ($FILE)" >&2; exit 1
fi
echo "Source file: $FILE"
echo "  contains: ${SUMMARY#OK }"
echo "Target row: $ROW"

# 2) Fresh pre-restore backup of the TARGET row (so this restore is reversible).
PRE="$DIR/builder_state-row${ROW}-PRE-RESTORE-${TS}.json"
HTTP=$(curl -s -o "$PRE" -w "%{http_code}" \
  "$SB_URL/rest/v1/builder_state?id=eq.${ROW}&select=data,history" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY")
if [[ "$HTTP" != "200" ]]; then echo "ERROR: could not back up target row (http $HTTP)" >&2; rm -f "$PRE"; exit 1; fi
echo "Pre-restore backup of row $ROW saved: $PRE"

# 3) Confirm (unless --yes).
if [[ "$YES" != "--yes" ]]; then
  read -r -p "Overwrite row $ROW with this file? Type the row number to confirm: " ANS
  [[ "$ANS" == "$ROW" ]] || { echo "Aborted."; exit 1; }
fi

# 4) Build the PATCH payload {data, history} from the file and write it.
PAYLOAD=$(python3 - "$FILE" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))[0]
print(json.dumps({"data": r["data"], "history": r.get("history") or []}))
PY
)
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$SB_URL/rest/v1/builder_state?id=eq.${ROW}" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  --data "$PAYLOAD")
if [[ "$HTTP" != "204" && "$HTTP" != "200" ]]; then
  echo "ERROR: PATCH failed (http $HTTP). Row unchanged or partial — restore from $PRE if needed." >&2; exit 1
fi

# 5) Verify the live row now matches the file.
curl -s "$SB_URL/rest/v1/builder_state?id=eq.${ROW}&select=data" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -o /tmp/restore_check.json
VERIFY=$(python3 - "$FILE" /tmp/restore_check.json <<'PY'
import json, sys, hashlib
want = json.load(open(sys.argv[1]))[0]['data']
live = json.load(open(sys.argv[2]))[0]['data']
h = lambda d: hashlib.md5(json.dumps(d, sort_keys=True).encode()).hexdigest()
wc, lc = len(want.get('cues') or []), len(live.get('cues') or [])
ok = h(want) == h(live)
print(("MATCH" if ok else "MISMATCH") + f" file_cues={wc} live_cues={lc}")
PY
)
echo "Verification: $VERIFY"
if [[ "$VERIFY" == MATCH* ]]; then
  echo "✓ Restore complete and verified. Row $ROW now matches the file."
  echo "  Undo path: bash restore_beb.sh \"$PRE\" $ROW"
else
  echo "✗ Restore verification FAILED — live row does not match the file. Investigate before trusting." >&2
  exit 1
fi
