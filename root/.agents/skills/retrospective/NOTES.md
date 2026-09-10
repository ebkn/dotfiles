# retrospective — implementation notes

The skill (`SKILL.md`, `/retrospective`) reviews recent Claude Code sessions for
inefficiency and permission behaviour. This file is about the two scripts behind
it.

## Why the scripts live here and not in bin/

They exist only for this skill, but are still linked into `~/.local/bin` by
`links.sh`: the skill runs from whatever project the session is in, and naming
them by absolute path would bake `$HOME` into the Bash prefixes in
`allowed-tools` (`Bash(session-review *)`, `Bash(session-extract *)`; a bare
`Bash` grant would widen permissions for as long as the skill runs, per
`c357c90`).

## session-extract

Reduces one transcript under `~/.claude/projects/` to a one-line JSON summary,
streaming via `jq -n 'reduce inputs'` (7 MB in 0.15 s).

It decides only what that session alone determines, so **a cached summary is
never rewritten**.

## session-review

Aggregates across sessions — median/p90/max (**never a mean**: one 30-hour
session drags it to describe nobody), outliers named by transcript **and path**,
a weekly series, and totals for the rare permission events — into
`~/.cache/session-review/v<N>/`.

Outside the repo for the same reason `textlint-docs` keeps its cache out (`bin/`
is symlinked in).

**Bump `v<N>` and `schema` together whenever the summary changes.** The cache is
also invalidated when `session-extract` is newer than an entry, so a metric added
later cannot read as uniformly zero.

## Every metric carries a tier

| Tier | Meaning |
| --- | --- |
| 1 | a count over records |
| 2 | a pattern over command text (heuristic; a heredoc body containing `rm -rf` trips it) |
| 3 | this repo's conventions and a word list |

## Findings from real data that shape the code, each pinned by a test

1. **A `user` record without `toolUseResult` is not necessarily typed.** The
   harness injects skill bodies and their caveats (`isMeta`), compaction
   summaries (`isCompactSummary`), slash-command echo (`<command-name>`,
   `<command-message>`, `<local-command-*>`) and task notifications as user
   records; on one session fewer than half of 124 "turns" were typed.
   `user_turns` and `--human-turns` share one definition so the count and the
   text cannot disagree.
2. **Subagent runs are separate `agent-*.jsonl` files carrying the parent's
   `sessionId`**, with one user turn by construction — identity comes from the
   filename, and they are excluded by default (`--include-subagents`).
3. **Sessions run from Claude's own scratch area** (`/tmp/claude-<uid>/…`, e.g.
   evals of this skill) are excluded by default (`--include-scratch`); 32 of them
   once pulled a week's median to one tool call. *The reviewer is the thing most
   likely to pollute what it measures.*
4. The store also holds non-transcript `.jsonl` (`skill-injections.jsonl` ×127,
   workflow journals) under the same dirs, with timestamps but no `sessionId`;
   the cache is keyed on the path under `projects/`, not the basename.
5. **Denials are classified from the structured `toolDenialKind`**
   (`permission-rule` / `user-rejected` / `automode-blocked` /
   `automode-unavailable`); the result text is only a fallback, having misfiled
   real user rejections.
6. **`retries_after_denial` is the metric the skill exists for** — a denied Bash
   call followed within three calls by one of the same intent class (`rm` →
   `git clean`, `reset --hard` → `reset`, `--command "UPDATE"` → `--file`). Any
   non-zero value is a finding.
7. `tool_result_bytes` sizes the `tool_result` block the model saw, not the
   harness-internal `toolUseResult`, which for Edit carries the original file and
   ran 24× the block.
8. Bash results carry no exit code, so `bash_error_rate` counts only non-empty
   stderr and **under-counts**.

## Two traps in editing

1. `session-review` is one long single-quoted jq program, so **an apostrophe in a
   jq comment ends the shell string** and every test fails at once. It has
   happened twice, and the test now runs `bash -n` first and says so by name.
2. **A `| strings`-style filter inside an `if` condition yields `empty` on a
   missing key**, which makes the reduce step empty and the accumulator `null`,
   so the extractor dies on the *next* record with a message about iterating
   null.

## Testing

`session-extract.test.sh` and `session-review.test.sh` run against **synthetic**
transcripts, not the real store: a real transcript carries work-repo source and
runs to megabytes, and the live store is written to while the test runs (the
current session appends to its own transcript), so two runs over real data
legitimately differ and determinism could not be asserted there.

The fixture reproduces every shape that made real data hard to parse — six Bash
result key sets, `isSidechain` both `false` and absent, heredoc bodies in
commands, a bare-string `toolUseResult`, each injected user-record kind, denials
with and without `toolDenialKind`, a plain `Exit code 1` error, a
`<command-message>`-first echo. **The generator omits `toolDenialKind` unless
set**, because stamping it on every result once hid a crash on the first real
error record.

The reporter test builds a `projects/` dir with subagent, scratch (two uids),
same-basename and non-transcript files, and asserts the exclusions, the absence
of any `"mean"`, tiers on every metric, `source_path` in the text report, cache
invalidation on a newer extractor, that `missing_weeks` is clamped to the window,
and that a cache-free run reproduces a cached one byte for byte.

Both run in CI.

The skill body states the read-only contract with concrete commands (Codex
ignores `allowed-tools` — see `root/README.md`), and the boundary is verified
headless with `--permission-mode acceptEdits` in a throwaway repo: the agent must
decline `RETRO.md` and `CLAUDE.md` writes with data in hand.

The trigger and boundary evals (12 near-miss prompts; two headless runs asking
the skill to write) live only in a scratchpad runner until `claude plugin eval`
leaves early access — they cost agent runs and are not in CI.
