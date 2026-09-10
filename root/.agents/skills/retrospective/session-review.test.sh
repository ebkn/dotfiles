#!/bin/bash
# Output-contract test for bin/session-review.
#
# Runs against a synthetic transcript dir rather than the real store, because
# the live store is being written to while the test runs -- the current session
# appends to its own transcript, so two consecutive runs over real data
# legitimately differ and determinism cannot be asserted there.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
review="$here/session-review"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

projects="$tmp/projects/-repo"
mkdir -p "$projects"
export CLAUDE_PROJECTS_DIR="$tmp/projects"
export XDG_CACHE_HOME="$tmp/cache"

# One session: `users` human turns, then `calls` Bash round trips.
mk_session() {
  out="$1"; sid="$2"; day="$3"; users="$4"; calls="$5"
  : > "$out"
  i=1
  while [ "$i" -le "$users" ]; do
    printf '{"type":"user","sessionId":"%s","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"%sT00:00:0%s.000Z","uuid":"u%s","message":{"role":"user","content":"go"}}\n' \
      "$sid" "$day" "$i" "$i" >> "$out"
    i=$((i + 1))
  done
  i=1
  while [ "$i" -le "$calls" ]; do
    printf '{"type":"assistant","sessionId":"%s","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"%sT00:01:0%s.000Z","uuid":"a%s","message":{"role":"assistant","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":1},"content":[{"type":"tool_use","id":"t%s","name":"Bash","input":{"command":"pwd"}}]}}\n' \
      "$sid" "$day" "$i" "$i" "$i" >> "$out"
    printf '{"type":"user","sessionId":"%s","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"%sT00:02:0%s.000Z","uuid":"r%s","toolUseResult":{"stdout":"/repo","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t%s"}]}}\n' \
      "$sid" "$day" "$i" "$i" "$i" >> "$out"
    i=$((i + 1))
  done
}

# Five ordinary sessions plus one that does far more work, so a p90 outlier
# exists at all. Outlier detection needs at least five samples by design.
mk_session "$projects/s1.jsonl" S1 2026-08-03 2 1
mk_session "$projects/s2.jsonl" S2 2026-08-03 2 2
mk_session "$projects/s3.jsonl" S3 2026-08-03 2 3
mk_session "$projects/s4.jsonl" S4 2026-08-03 2 4
mk_session "$projects/s5.jsonl" S5 2026-08-03 2 5
# A fortnight later, leaving a week with nothing in it.
mk_session "$projects/s6.jsonl" S6 2026-08-17 1 9
# A subagent run: its own file, but it carries the parent's session id and has
# exactly one user turn. Must not be counted as a session.
mk_session "$projects/agent-abc123.jsonl" S1 2026-08-03 1 9

run() { "$review" --days 3650 --json "$@"; }

a="$tmp/a.json"; b="$tmp/b.json"; c="$tmp/c.json"
run > "$a"
run > "$b"
run --no-cache > "$c"

fail=0
assert() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}
q() { jq -r "$1" "$a"; }

assert "subagent transcripts are not sessions" 6 "$(q .session_count)"
assert "subagent transcripts are counted"      1 "$(q .subagent_transcripts)"
assert "and reported as excluded"          false "$(q .subagents_included)"
assert "--include-subagents counts them"       7 "$("$review" --days 3650 --json --include-subagents | jq -r .session_count)"

# The mean is deliberately absent: one 30-hour session drags it far enough to
# describe nobody, and the report exists to surface the ends, not the middle.
assert "no mean anywhere in the output" 0 "$(grep -c '"mean"' "$a" || true)"
assert "median is reported"          true "$(q '.distributions.tool_calls | has("median")')"
assert "p90 is reported"             true "$(q '.distributions.tool_calls | has("p90")')"

# Every metric states how much of the truth it can see. Tier 1 is decided by
# record counts alone; Tier 2 and 3 will be partial and must say so.
assert "every distribution carries a tier" 0 \
  "$(q '[.distributions | to_entries[] | select(.value != null) | select(.value | has("tier") | not)] | length')"

# Permission and safety metrics carry the tier of what they rest on: denial
# records (1), command-text patterns (2), this repo's conventions (3). Totals
# exist because a median of zero says nothing about events that are rare.
assert "denials are tier 1"            1 "$(q .distributions.retries_after_denial.tier)"
assert "risk patterns are tier 2"      2 "$(q .distributions.risky_commands.tier)"
assert "conventions are tier 3"        3 "$(q .distributions.compound_cd.tier)"
assert "totals carry denials by kind" true "$(q '.totals.denials | has("classifier")')"
assert "totals carry retries"          0 "$(q .totals.retries_after_denial)"

# An outlier has to name a file that can actually be opened. The session id
# cannot do that: a subagent transcript carries its parent's id.
assert "outliers exist"                 true "$(q '(.outliers | length) > 0')"
assert "outliers name a transcript"        0 \
  "$(q '[.outliers[] | select(has("transcript") | not)] | length')"
assert "the busy session is an outlier" true \
  "$(q '[.outliers[] | select(.metric == "tool_calls") | .transcript] | index("s6") != null')"

# Gaps are load-bearing: the real store has whole months missing, and a series
# read without them looks continuous when it is not.
assert "the empty week is reported" true "$(q '(.missing_weeks | length) > 0')"

assert "two cached runs agree"            same "$(if cmp -s "$a" "$b"; then echo same; else echo differ; fi)"
# Re-derivable from the transcripts alone: throwing the cache away must not
# change a single number, or the cache has become the source of truth.
assert "a cache-free run agrees with it"  same "$(if cmp -s "$a" "$c"; then echo same; else echo differ; fi)"

exit "$fail"
