#!/bin/bash
GUARD_STATE_DIR="${GUARD_STATE_DIR:-$HOME/.claude/guardrails}"
GUARD_CONFIG="${GUARD_CONFIG:-$GUARD_STATE_DIR/guard.conf}"
GUARD_TTL="${GUARD_TTL:-600}"
mkdir -p "$GUARD_STATE_DIR" 2>/dev/null

guard_log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" >> "$GUARD_STATE_DIR/guard.log" 2>/dev/null
}

# json_get '<json>' 'tool_input.file_path' -> string or empty. Input via pipe, never a heredoc.
json_get() {
    printf '%s' "$1" | GUARD_KEY="$2" python3 -c '
import sys, json, os
try:
    d = json.load(sys.stdin)
    for k in os.environ["GUARD_KEY"].split("."):
        d = d.get(k, "") if isinstance(d, dict) else ""
    print(d if isinstance(d, str) else "")
except Exception:
    print("")
'
}
