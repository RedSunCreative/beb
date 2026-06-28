#!/usr/bin/env bash
# backup_beb.sh — independent off-app backup of the BEB Supabase row.
#
# Why this exists: the app's own localStorage + Supabase row are both overwritten
# on every save. This script pulls the live row and writes a TIMESTAMPED, immutable
# copy to ./backups/ — a floor that survives any app bug. Run it anytime, or
# schedule it (cron / launchd) for automatic periodic backups.
#
# Usage:
#   bash backup_beb.sh            # backs up the current episode row (99 = E9)
#   bash backup_beb.sh 98         # back up a specific row id
#
# Restore: the saved JSON is the row's {data, history}. To restore, PATCH it back:
#   curl -X PATCH "$SB_URL/rest/v1/builder_state?id=eq.<ROW>" \
#     -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
#     -H "Content-Type: application/json" -H "Prefer: return=minimal" \
#     --data @backups/<file>.json
# (The file already has the {data, history} shape PATCH expects.)
# ALWAYS take a fresh backup immediately before restoring, and verify counts after.

set -euo pipefail

ROW="${1:-99}"
SB_URL="https://gogudwpuhmidngsbqfjg.supabase.co"
KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdvZ3Vkd3B1aG1pZG5nc2JxZmpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3MTQ2NTMsImV4cCI6MjA5NDI5MDY1M30.O6n_tRQsMU29wFV_RArcN9n6gP8KSDWJQqM4P6cTq3s"

DIR="$(cd "$(dirname "$0")" && pwd)/backups"
mkdir -p "$DIR"
TS="$(date +%Y-%m-%d_%H%M%S)"
OUT="$DIR/builder_state-row${ROW}-${TS}.json"

echo "Backing up row $ROW from Supabase…"
HTTP=$(curl -s -o "$OUT" -w "%{http_code}" \
  "$SB_URL/rest/v1/builder_state?id=eq.${ROW}&select=data,history" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY")

if [[ "$HTTP" != "200" ]]; then
  echo "ERROR: Supabase returned HTTP $HTTP — backup NOT saved." >&2
  rm -f "$OUT"
  exit 1
fi

# Verify it actually contains cue data, and report counts as a sanity check.
python3 - "$OUT" <<'PY'
import json, sys
p = sys.argv[1]
rows = json.load(open(p))
if not rows or not isinstance(rows, list) or not rows[0].get('data'):
    print("ERROR: backup file has no data — refusing to keep an empty backup.", file=sys.stderr)
    sys.exit(1)
data = rows[0]['data']
cues = data.get('cues') or []
guests = data.get('guests') or []
crew = data.get('crew') or []
hist = rows[0].get('history') or []
if len(cues) < 1:
    print(f"ERROR: backup has {len(cues)} cues — refusing to keep an empty cue list.", file=sys.stderr)
    sys.exit(1)
print(f"  OK: E{data.get('epNum')} — {data.get('epTitle')}")
print(f"  cues: {len(cues)} | guests: {len(guests)} | crew: {len(crew)} | history snapshots: {len(hist)}")
PY

# Keep the last 60 backups for this row; prune older ones.
ls -1t "$DIR"/builder_state-row${ROW}-*.json 2>/dev/null | tail -n +61 | xargs -I{} rm -f {} 2>/dev/null || true

echo "Saved: $OUT"
