#!/bin/bash
# PreToolUse (matcher: Bash). Blocks `git add <gated file>` only when NEW ids were added
# relative to HEAD and no evaluation marker exists for today. Removals, archive moves and
# field updates are not gated. Unreadable on either side -> fail closed.
#   GATED_FILE      path relative to the repo root (JSON)
#   GATED_LIST_KEY  top-level list key, default "items"
#   GATED_ID_KEY    id field inside each item, default "id"
DIR="$(cd "$(dirname "$0")" && pwd)"; . "$DIR/lib.sh"
input=$(cat)
[ -z "$GATED_FILE" ] && exit 0
cmd=$(json_get "$input" tool_input.command)
[ "$(json_get "$input" tool_name)" = Bash ] || exit 0

hit=$(GATED_FILE="$GATED_FILE" CMD="$cmd" python3 -c '
import os, re
frag, cmd = os.environ["GATED_FILE"], os.environ["CMD"]
for seg in re.split(r"&&|;|\|", cmd):
    t = seg.split()
    if len(t) >= 2 and t[0] == "git" and t[1] == "add" and frag in seg:
        print("yes"); raise SystemExit
print("no")
')
[ "$hit" = yes ] || exit 0

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "EVAL GATE: not in a git repo, failing closed" >&2; exit 2; }
added=$(ROOT="$root" REL="$GATED_FILE" KEY="${GATED_LIST_KEY:-items}" IDK="${GATED_ID_KEY:-id}" python3 -c '
import os, json, subprocess
root, rel, key, idk = os.environ["ROOT"], os.environ["REL"], os.environ["KEY"], os.environ["IDK"]
def ids(text):
    try: return {i.get(idk) for i in json.loads(text).get(key, [])}
    except Exception: return None
try: now = ids(open(os.path.join(root, rel)).read())
except Exception: now = None
try: head = ids(subprocess.run(["git", "show", "HEAD:" + rel], cwd=root, capture_output=True, text=True, check=True).stdout)
except Exception: head = None
print("yes" if now is None or head is None or (now - head) else "no")
')
[ "$added" = yes ] || { echo "(eval-gate: no new ids, not gated)"; exit 0; }
MARKER="$GUARD_STATE_DIR/eval-$(date +%Y%m%d).marker"
if [ ! -f "$MARKER" ]; then
    guard_log "EVAL-GATE blocked git add of new ids in $GATED_FILE"
    echo "EVAL GATE: new ids in $GATED_FILE and no evaluation marker for today ($MARKER)." >&2
    exit 2
fi
exit 0
