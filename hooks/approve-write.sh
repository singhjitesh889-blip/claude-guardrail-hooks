#!/bin/bash
# approve-write.sh <absolute-file-path> "<reason>"
# Mints a single-use token (default 10 min) for exactly one file. Run it only after the
# human has approved that specific change in chat. Tokens are a list, so a second
# approval never overwrites a pending first one.
DIR="$(cd "$(dirname "$0")" && pwd)"; . "$DIR/lib.sh"
FILE_PATH="$1"; REASON="${2:-no reason given}"
[ -z "$FILE_PATH" ] && { echo "usage: approve-write.sh <absolute-file-path> \"<reason>\"" >&2; exit 1; }
python3 -c '
import sys, json, time
fp, reason, tf, ttl = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
try:
    tokens = json.load(open(tf))
    if not isinstance(tokens, list): tokens = []
except Exception:
    tokens = []
now = int(time.time())
tokens = [t for t in tokens if (now - t.get("ts", 0)) <= ttl and t.get("file") != fp]
tokens.append({"file": fp, "ts": now, "reason": reason})
json.dump(tokens, open(tf, "w"))
' "$FILE_PATH" "$REASON" "$GUARD_STATE_DIR/approvals.json" "$GUARD_TTL"
guard_log "APPROVED -- $FILE_PATH -- $REASON"
echo "Approved: $FILE_PATH (single-use, ${GUARD_TTL}s)"
