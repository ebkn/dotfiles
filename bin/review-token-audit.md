# review-token-audit — token usage of the review forks

`bin/review-token-audit [--days N]` sums every assistant record's token usage
over the last `N` days of mtimes (default 14) in `~/.claude/projects`:

- **forks** (`*/subagents/agent-*.jsonl`) are keyed by the skill each one
  carries (matched from `skills/<name>` in the fork's brief), with a
  `fork/<skill>` row each — skips, not just `review-*`, so `session-summary`,
  `update-pr` and eval fixtures (`eval/<name>`) appear too;
- **main sessions** (`<session>.jsonl`) are summed into the `main-total` line —
  once each, so shares recomputed from the table do not double-count — because
  their usage is not attributable per skill.

It exists because **the standard aggregates hide the review forks**:
`session-review` excludes subagent transcripts by default, so the largest
token consumers of a session are invisible in it — measured 2026-11-10, forks
were 29% of all output tokens and 34% of all cache-new while `session-review
--days 30` showed none of them. The companion doc
`root/review-breakpoints.md` cites this script as its instrument: the day-7
re-measure after the breakpoints policy lands must run the same script that
produced the baseline, so the before/after differ by behaviour, not by tool.

The relapse decision reads **both** of the last two blocks —
`root/review-breakpoints.md` pulls the reserved PostToolUse hook out of its
reserve when forks/session climbs past ~3, or a single session exceeds ~6, on
a re-measure:

- `forks: F over K forked sessions, S main sessions in window` and the two
  mean lines are the decision row. It prints **both** means because the
  thresholds were written as "forks/session" without picking a population:
  per main session (0-fork ones included) is what a whole-week window sees,
  per forked session is the inflated one a run that barely reviews reads, and
  the doc does not commit to either.
- `sessions by fork count (>=3)` is the outlier list: the per-session half of
  the threshold — one bad session tripping the hook without moving a mean —
  reads here, not from the mean.

Cost attribution limits worth knowing when reading the table:

- **cache_read dominates everything** — with prompt caching re-reading is the
  bulk of billed tokens, so the `cache_read(M)` column is what moves a bill;
- **`output(M)` is what the review loop actually multiplies** — each round
  re-reads the code (cache-read) and writes findings (not cacheable);
- **`sessions` counts parent sessions, not distinct repos**, and a session id
  can appear in several project directories after a session moves;
- **forks and mains with zero assistant records are skipped** (no usage), so
  `runs` may sit below a raw `find | wc -l`.

## Testing it

There is no test suite: the script's input is gitignored transcript weights
under `$HOME/.claude/projects`, which a fixture cannot recreate honestly, and
its output aggregates the same `jq` reads the session measurement used
(`root/review-breakpoints.md`). What CI does check is handled where it lives:
`bin/lint-shell` shellchecks the script and `bin/test` runs everything,
CI included. If a row name looks wrong (`eval/`, `other-fork`), rerun with a
larger `--days` before suspecting the code.
