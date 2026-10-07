#!/bin/bash
# End-to-end tests: every case feeds a hook real JSON on stdin, exactly as Claude Code does.
H="$(cd "$(dirname "$0")/../hooks" && pwd)"
T=$(mktemp -d); export GUARD_STATE_DIR="$T/state"; export GUARD_CONFIG="$T/state/guard.conf"
mkdir -p "$T/state"; TAB=$'\t'
pass=0; fail=0
check() { # name expected_exit actual_exit
    if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1 (expected exit $2, got $3)"; fail=$((fail+1)); fi
}
write_json() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$1" "$2"; }
run_guard() { write_json "$1" "$2" | "$H/guard-protected-files.sh" 2>/dev/null; echo $?; }

printf 'block\t/rules/\tcold rules\nblock\t/CLAUDE\\.md$\thot-loaded config\nwarn\t/state/\tstate directory\ncontent\tCOMPILED\\.md$\t\\] MISTAKE\\b\tmistakes belong in the mistakes log\n' > "$GUARD_CONFIG"

echo "guard-protected-files"
check "unprotected file is allowed" 0 "$(run_guard /proj/src/app.js hello)"
check "protected file blocked with no token" 2 "$(run_guard /proj/rules/a.md hi)"
bash "$H/approve-write.sh" /proj/rules/a.md "test" >/dev/null
check "approved file passes once" 0 "$(run_guard /proj/rules/a.md hi)"
check "token is single-use (second write blocked)" 2 "$(run_guard /proj/rules/a.md hi)"
bash "$H/approve-write.sh" /proj/rules/a.md "test" >/dev/null
check "token for file A does not unlock file B" 2 "$(run_guard /proj/rules/b.md hi)"
check "...and A's token is still intact" 0 "$(run_guard /proj/rules/a.md hi)"
bash "$H/approve-write.sh" /proj/CLAUDE.md "x" >/dev/null; bash "$H/approve-write.sh" /proj/rules/c.md "y" >/dev/null
check "second approval does not overwrite first (CLAUDE.md)" 0 "$(run_guard /proj/CLAUDE.md hi)"
check "...nor lose the other (rules/c.md)" 0 "$(run_guard /proj/rules/c.md hi)"
GUARD_TTL=0 bash "$H/approve-write.sh" /proj/rules/d.md "x" >/dev/null; sleep 1
check "expired token is rejected" 2 "$(GUARD_TTL=0 bash -c "$(declare -f write_json run_guard); H=$H; run_guard /proj/rules/d.md hi")"
check "content guard blocks even with a fresh token" 2 "$(bash "$H/approve-write.sh" /proj/COMPILED.md x >/dev/null; run_guard /proj/COMPILED.md '- [2026] MISTAKE oops')"
check "content guard allows clean content" 0 "$(bash "$H/approve-write.sh" /proj/COMPILED.md x >/dev/null; run_guard /proj/COMPILED.md '- RULE ok')"
check "env bypass allows a blocked file" 0 "$(GUARD_SYSTEM_WRITE=1 run_guard /proj/rules/z.md hi)"
grep -q "BYPASS-ENV" "$T/state/guard.log"; check "...and the bypass was logged" 0 $?
check "warn-only path is allowed" 0 "$(run_guard /proj/state/s.md hi)"
check "KNOWN LIMIT: a Bash tool call never reaches this guard" 0 "$(printf '{"tool_name":"Bash","tool_input":{"command":"echo x > /proj/rules/a.md"}}' | "$H/guard-protected-files.sh" 2>/dev/null; echo $?)"

echo "registration-guard"
mkdir -p "$T/skills/alpha" "$T/agents"; echo "# a" > "$T/skills/alpha/SKILL.md"; echo "# b" > "$T/agents/beta.md"
echo "alpha and beta are listed here" > "$T/roster.md"
export COMPONENT_DIRS="$T/skills:$T/agents" ROSTER_FILES="$T/roster.md"
"$H/registration-guard.sh" >/dev/null 2>&1; check "first run seeds a baseline, no block" 0 $?
mkdir -p "$T/skills/gamma"; echo "# g" > "$T/skills/gamma/SKILL.md"
"$H/registration-guard.sh" >/dev/null 2>&1; check "new unreferenced skill blocks the turn" 2 $?
"$H/registration-guard.sh" >/dev/null 2>&1; check "...blocks a second time" 2 $?
"$H/registration-guard.sh" >/dev/null 2>&1; check "...circuit breaker releases on the third" 0 $?
mkdir -p "$T/skills/delta"; echo "# d" > "$T/skills/delta/SKILL.md"; echo "delta" >> "$T/roster.md"
"$H/registration-guard.sh" >/dev/null 2>&1; check "new skill that IS in the roster passes" 0 $?
mkdir -p "$T/skills/delta-v2"; echo "# d2" > "$T/skills/delta-v2/SKILL.md"
"$H/registration-guard.sh" >/dev/null 2>&1; check "hyphen-aware: 'delta' does not satisfy 'delta-v2'" 2 $?
"$H/registration-guard.sh" --banner >/dev/null 2>&1; check "banner mode never blocks" 0 $?
rm -f "$T/state/known-components.txt" "$T/state/component-blocks.txt"; "$H/registration-guard.sh" >/dev/null 2>&1
printf 'shape\t%s\t^.{200}.{101,}$\tmemory lines must be one line, 300 chars or fewer\n' "$T/memory.md" >> "$GUARD_CONFIG"
python3 -c "print('x'*320)" > "$T/memory.md"
"$H/registration-guard.sh" >/dev/null 2>&1; check "content-shape rule blocks an over-long memory line" 2 $?
printf 'dupe\t%s\t^Rule #[0-9]+\n' "$T/rules.md" >> "$GUARD_CONFIG"; printf 'Rule #1 a\nRule #1 b\n' > "$T/rules.md"
rm -f "$T/state/component-blocks.txt"; echo ok > "$T/memory.md"
"$H/registration-guard.sh" >/dev/null 2>&1; check "duplicate-label rule blocks" 2 $?
unset COMPONENT_DIRS ROSTER_FILES

echo "diff-gated-commit"
G="$T/repo"; mkdir -p "$G"; cd "$G"; git init -q; git config user.email t@t; git config user.name t
echo '{"items":[{"id":"a"},{"id":"b"}]}' > db.json; git add db.json; git commit -qm init
export GATED_FILE=db.json
gate() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | "$H/diff-gated-commit.sh" >/dev/null 2>&1; echo $?; }
echo '{"items":[{"id":"a"},{"id":"b"},{"id":"c"}]}' > db.json
check "new id + no marker blocks git add" 2 "$(gate 'git add db.json')"
check "unrelated command is ignored" 0 "$(gate 'grep db.json notes.txt')"
check "git add of another file is ignored" 0 "$(gate 'git add other.txt')"
touch "$GUARD_STATE_DIR/eval-$(date +%Y%m%d).marker"
check "new id + marker today passes" 0 "$(gate 'git add db.json')"
rm "$GUARD_STATE_DIR/eval-$(date +%Y%m%d).marker"
echo '{"items":[{"id":"a"}]}' > db.json
check "removal only is not gated" 0 "$(gate 'git add db.json')"
echo 'not json' > db.json
check "unreadable file fails closed" 2 "$(gate 'git add db.json')"
cd - >/dev/null; rm -rf "$T"
echo; echo "$pass passed, $fail failed"; [ $fail = 0 ]
