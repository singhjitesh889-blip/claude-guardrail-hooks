#!/bin/bash
# PreToolUse (matcher: Write|Edit). Config rows are tab-separated:
#   block<TAB>path-regex<TAB>reason     hard-block unless a single-use approval token exists
#   warn<TAB>path-regex<TAB>reason      allow, but print a warning
#   content<TAB>path-regex<TAB>forbidden-content-regex<TAB>reason   block always, token or not
DIR="$(cd "$(dirname "$0")" && pwd)"; . "$DIR/lib.sh"
TAB=$'\t'
input=$(cat)
file_path=$(json_get "$input" tool_input.file_path)
[ -z "$file_path" ] && exit 0
written="$(json_get "$input" tool_input.content)$(json_get "$input" tool_input.new_string)"
[ -f "$GUARD_CONFIG" ] || exit 0

while IFS="$TAB" read -r kind a b c; do
    [ "$kind" = content ] || continue
    if echo "$file_path" | grep -qE "$a" && printf '%s' "$written" | grep -qE "$b"; then
        guard_log "CONTENT-BLOCK $file_path -- $c"
        echo "CONTENT GUARD: $c" >&2
        exit 2
    fi
done < "$GUARD_CONFIG"

is_blocked=0; reason=""; warn_reason=""
while IFS="$TAB" read -r kind a b; do
    case "$kind" in
        block) [ $is_blocked = 0 ] && echo "$file_path" | grep -qE "$a" && { is_blocked=1; reason="$b"; } ;;
        warn)  [ -z "$warn_reason" ] && echo "$file_path" | grep -qE "$a" && warn_reason="$b" ;;
    esac
done < "$GUARD_CONFIG"

if [ "${GUARD_SYSTEM_WRITE:-}" = "1" ]; then
    [ $is_blocked = 1 ] && guard_log "BYPASS-ENV overrode block on '$reason' -- $file_path"
    exit 0
fi

if [ $is_blocked = 1 ]; then
    approved=$(python3 -c '
import sys, json, time
fp, tf, ttl = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    tokens = json.load(open(tf))
    if not isinstance(tokens, list): tokens = []
except Exception:
    tokens = []
now = int(time.time()); keep = []; hit = False
for t in tokens:
    live = (now - t.get("ts", 0)) <= ttl
    if not hit and live and t.get("file") == fp:
        hit = True; continue
    if live: keep.append(t)
if hit: json.dump(keep, open(tf, "w"))
print("yes" if hit else "no")
' "$file_path" "$GUARD_STATE_DIR/approvals.json" "$GUARD_TTL")
    if [ "$approved" = "yes" ]; then
        guard_log "TOKEN-CONSUMED -- $file_path"
        exit 0
    fi
    {
        echo "PLAN GATE: blocked write to $reason"
        echo "  File: $file_path"
        echo "  Say what you intend to change and why, and get the human's approval."
        echo "  Then: bash $DIR/approve-write.sh \"$file_path\" \"<reason>\""
    } >&2
    exit 2
fi

[ -n "$warn_reason" ] && echo "GUARD WARNING: writing to $warn_reason" >&2
exit 0
