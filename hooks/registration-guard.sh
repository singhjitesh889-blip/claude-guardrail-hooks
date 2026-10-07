#!/bin/bash
# Stop hook: a skill/agent that is NEW since the last snapshot must be mentioned in a roster
# file, or the turn cannot end. Circuit breaker: at most 2 blocks per component, then it stops
# blocking so it can never deadlock a session. --banner mode (SessionStart) never blocks.
#   COMPONENT_DIRS  colon-separated dirs holding <name>/SKILL.md or <name>.md
#   ROSTER_FILES    colon-separated files that must mention every component by name
# Config rows (tab-separated, optional):
#   shape<TAB>file<TAB>forbidden-regex<TAB>reason
#   dupe<TAB>file<TAB>label-regex             the same label assigned twice in one file
# Known ceiling: this proves a name is MENTIONED, not that the mention is accurate.
DIR="$(cd "$(dirname "$0")" && pwd)"; . "$DIR/lib.sh"
TAB=$'\t'
MODE="stop"; [ "$1" = "--banner" ] && MODE="banner"
KNOWN="$GUARD_STATE_DIR/known-components.txt"
BLOCKS="$GUARD_STATE_DIR/component-blocks.txt"
IGNORE="$GUARD_STATE_DIR/ignore-components.txt"
IFS=':' read -r -a DIRS <<< "${COMPONENT_DIRS:-}"
IFS=':' read -r -a ROSTERS <<< "${ROSTER_FILES:-}"

is_referenced() { grep -qE "(^|[^A-Za-z0-9_-])$1([^A-Za-z0-9_-]|\$)" "${ROSTERS[@]}" 2>/dev/null; }
is_ignored() { [ -f "$IGNORE" ] && grep -qxF "$1" "$IGNORE"; }
block_count() { local c=0; [ -f "$BLOCKS" ] && c=$(grep -c "^$1\$" "$BLOCKS"); echo "${c:-0}"; }

names=""
for d in "${DIRS[@]}"; do
    for f in "$d"/*/SKILL.md "$d"/*.md; do
        [ -e "$f" ] || continue
        case "$f" in */SKILL.md) n=$(basename "$(dirname "$f")");; *) n=$(basename "$f" .md);; esac
        names="$names $n"
    done
done

if [ ! -f "$KNOWN" ]; then
    : > "$KNOWN"; for n in $names; do echo "$n" >> "$KNOWN"; done
    [ "$MODE" = banner ] && echo "(registration-guard: baseline seeded with $(wc -l < "$KNOWN" | tr -d ' ') components)"
    exit 0
fi

unwired=""
for n in $names; do
    grep -qxF "$n" "$KNOWN" && continue
    if is_ignored "$n" || is_referenced "$n"; then echo "$n" >> "$KNOWN"; continue; fi
    unwired="$unwired $n"
done

violations=""
if [ -f "$GUARD_CONFIG" ]; then
    while IFS="$TAB" read -r kind file a b; do
        case "$kind" in
            shape) [ -f "$file" ] && grep -qE "$a" "$file" && violations="$violations\n  - $(basename "$file"): $b" ;;
            dupe)  [ -f "$file" ] && [ -n "$(grep -oE "$a" "$file" | sort | uniq -d)" ] && violations="$violations\n  - $(basename "$file"): duplicate label, renumber one" ;;
        esac
    done < "$GUARD_CONFIG"
fi

out=""
for n in $unwired; do
    if [ "$MODE" = stop ] && [ "$(block_count "$n")" -lt 2 ]; then
        echo "$n" >> "$BLOCKS"; out="$out\n  - $n is not mentioned in any roster file"
    elif [ "$MODE" = banner ]; then out="$out\n  - $n is not mentioned in any roster file"; fi
done
if [ -n "$violations" ]; then
    key="__shape__"
    if [ "$MODE" = banner ] || [ "$(block_count $key)" -lt 2 ]; then
        [ "$MODE" = stop ] && echo "$key" >> "$BLOCKS"; out="$out$violations"
    fi
fi

if [ -n "$out" ]; then
    guard_log "REGISTRATION $MODE:$(printf '%b' "$out" | tr '\n' ' ')"
    printf 'REGISTRATION GUARD:%b\n' "$out" >&2
    [ "$MODE" = stop ] && exit 2
fi
exit 0
