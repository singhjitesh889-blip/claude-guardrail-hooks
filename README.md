# claude-guardrail-hooks

Prose rules get violated. A rule that lives only in a markdown file is a request, not a control. These four scripts turn the rules that matter into things the harness enforces: a protected file cannot be written without a single-use approval, a new skill or agent cannot be left out of the docs, and a data file cannot ship new records without an evaluation on record.

Bash and python3 only. No dependencies. Every behaviour below is covered by a test that feeds the hook real JSON on stdin, exactly as Claude Code does.

```bash
bash tests/run.sh
```

## The four scripts

| Hook | Event | What it does |
|---|---|---|
| `guard-protected-files.sh` | PreToolUse, `Write\|Edit` | Hard-blocks (exit 2) writes to files matching a protected pattern unless a single-use, file-specific approval token exists. Also enforces content rules that no token can override. |
| `approve-write.sh` | run by hand | Mints that token after a human has approved one specific change. Single-use, expires in 10 minutes, stored as a list so a second approval never overwrites a pending first. |
| `registration-guard.sh` | Stop and SessionStart | A skill or agent that is new since the last snapshot must be mentioned in a roster file, or the turn cannot end. Includes declarative content-shape and duplicate-label rules. |
| `diff-gated-commit.sh` | PreToolUse, `Bash` | Blocks `git add <data file>` only when new IDs were added since HEAD and no evaluation marker exists for today. |

## Design decisions worth stealing

**Tokens, not toggles.** The first version of a bypass is usually an environment variable. It works until a stray `export` in a terminal silently defeats every protection with no trace. Here the environment bypass exists for headless automation, and it logs every time it actually overrides a block. The interactive path is a token: one file, one use, ten minutes, logged on issue and on consumption.

**Gate the diff, not the touch.** The commit gate used to fire on any `git add` of the data file, so cleanups and archive moves got blocked by a gate that had nothing to say about them. It now compares the IDs in the working tree against HEAD and blocks only when IDs were *added*. If either side is unreadable it fails closed.

**Detect "new" by snapshot, not by timestamp.** The registration guard first used file creation time to decide what was new. Editing a file through an editor tool resets that time on some filesystems, so every recently edited component looked newly created. A persisted name snapshot does not care about timestamps.

**A circuit breaker on every blocking hook that can loop.** A Stop hook that blocks forever deadlocks the session. After two blocks per component it releases and the banner carries the warning instead. Exit 2 stderr and SessionStart stdout are the loud channels; exit 0 output is invisible to the model.

**Contract rules as data, not scripts.** "This file must never contain X" and "this label must not appear twice" are rows in a config table, not a new hook each time.

## Test run

```
guard-protected-files
  PASS  unprotected file is allowed
  PASS  protected file blocked with no token
  PASS  approved file passes once
  PASS  token is single-use (second write blocked)
  PASS  token for file A does not unlock file B
  PASS  ...and A's token is still intact
  PASS  second approval does not overwrite first (CLAUDE.md)
  PASS  ...nor lose the other (rules/c.md)
  PASS  expired token is rejected
  PASS  content guard blocks even with a fresh token
  PASS  content guard allows clean content
  PASS  env bypass allows a blocked file
  PASS  ...and the bypass was logged
  PASS  warn-only path is allowed
  PASS  KNOWN LIMIT: a Bash tool call never reaches this guard
registration-guard
  PASS  first run seeds a baseline, no block
  PASS  new unreferenced skill blocks the turn
  PASS  ...blocks a second time
  PASS  ...circuit breaker releases on the third
  PASS  new skill that IS in the roster passes
  PASS  hyphen-aware: 'delta' does not satisfy 'delta-v2'
  PASS  banner mode never blocks
  PASS  content-shape rule blocks an over-long memory line
  PASS  duplicate-label rule blocks
diff-gated-commit
  PASS  new id + no marker blocks git add
  PASS  unrelated command is ignored
  PASS  git add of another file is ignored
  PASS  new id + marker today passes
  PASS  removal only is not gated
  PASS  unreadable file fails closed

30 passed, 0 failed
```

## Known limits (stated, not hidden)

- **A Bash write bypasses the file guard.** The guard matches `Write|Edit`. `cat > file`, `sed -i` or a python one-liner never reach it, and nothing is logged. There is a test that pins this as a known limit. Closing it means inspecting Bash commands for writes to protected paths, which is a heuristic and easy to get wrong in both directions.
- **The registration guard proves a name is mentioned, not that the mention is accurate.** A stale or wrong reference still passes. Semantic accuracy belongs to a periodic audit, not a grep-based hook.
- **It fires at the end of every turn,** not only at session end, which is why the circuit breaker exists.
- **Verifiers are not read-only unless the tools say so.** If you pair this with verifier agents, restricting their tools is what enforces it. A prompt only asks.

## Setup

1. Copy `examples/guard.conf` to `~/.claude/guardrails/guard.conf` and edit the patterns. Rows are tab-separated.
2. Merge `examples/settings.json` into your Claude Code settings and fix the paths.
3. Set `COMPONENT_DIRS` and `ROSTER_FILES` for the registration guard. State lives in `~/.claude/guardrails` unless `GUARD_STATE_DIR` is set.
4. After a human approves a protected edit: `bash hooks/approve-write.sh /absolute/path "reason"`.

MIT licensed.
