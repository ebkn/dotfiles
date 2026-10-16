# skill-eval-assert.sh — assertions an eval case sources from its assert.sh.
#
# Grading is one line per assertion, PASS or FAIL on stdout, and
# skill_eval_finish exits non-zero if any of them failed. bin/skill-eval greps
# those lines for the summary, so changing the output format means changing the
# runner too.
#
# Assert on the skill's observable contract -- what it wrote, what it refused to
# write, what the report says -- not on the exit status of `claude -p`, which is
# 0 for a run that did nothing useful.
#
# Sourced, so it declares no `set -e` / `set -o`: those would leak into the
# caller's shell (see .claude/rules/shell-scripts.md).
#
# Passed in by the runner:
#   SKILL_EVAL_TRANSCRIPT       path to the stream-json (JSONL) transcript
#   SKILL_EVAL_RESULT_FILE      path to the trailing result record alone
#   SKILL_EVAL_CLAUDE_BIN       claude to use for the check_llm judge
#   SKILL_EVAL_JUDGE_MODEL      judge model (default haiku)
#   SKILL_EVAL_JUDGE_COST_FILE  file the judge's cost is appended to
#
# shellcheck shell=bash

SKILL_EVAL_FAILED=0

# check <label> <command...>
# Grades on the command's exit status. Put a compound condition in a function
# and pass the function name.
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    SKILL_EVAL_FAILED=1
  fi
}

# check_eq <label> <expected> <actual>
check_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s (expected: %s, actual: %s)\n' "$label" "$expected" "$actual"
    SKILL_EVAL_FAILED=1
  fi
}

# check_match <label> <extended regex> <string>
check_match() {
  local label="$1" regex="$2" string="$3"
  if [[ "$string" =~ $regex ]]; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s (no match: %s)\n' "$label" "$regex"
    SKILL_EVAL_FAILED=1
  fi
}

# check_not_match <label> <extended regex> <string>
check_not_match() {
  local label="$1" regex="$2" string="$3"
  if [[ "$string" =~ $regex ]]; then
    printf 'FAIL  %s (matched: %s)\n' "$label" "$regex"
    SKILL_EVAL_FAILED=1
  else
    printf 'PASS  %s\n' "$label"
  fi
}

# --- reading the transcript ---

# How many calls were refused, which equals how many the skill attempted
# outside its allowed-tools.
transcript_denials() {
  jq '.permission_denials // [] | length' "$SKILL_EVAL_RESULT_FILE"
}

# Every command handed to the Bash tool, one call per line (newlines folded).
transcript_commands() {
  jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use" and .name == "Bash")
    | .input.command
    | gsub("\n"; "\\n")
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# The text of the final response.
transcript_result_text() {
  jq -r '.result // ""' "$SKILL_EVAL_RESULT_FILE"
}

# transcript_tool_uses <tool name>
# How many times that tool was called. An attempt that was refused still counts
# (transcript_denials is where refusals are read).
transcript_tool_uses() {
  jq -s --arg name "$1" '
    [ .[]
      | select(.type == "assistant")
      | .message.content[]?
      | select(.type == "tool_use" and .name == $name) ]
    | length
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# transcript_first_tool_index <tool name>
# 0-based index of the transcript record carrying the first call to that tool;
# empty when it was never called. Ordering is the only way left to see the
# skill's read-only boundary: the caller fixes and commits once the review is
# reported, so "never wrote" is no longer true of a whole run, while "wrote
# nothing before the report" still separates the skill from its caller.
transcript_first_tool_index() {
  jq -s --arg name "$1" '
    [ to_entries[]
      | select(.value.type == "assistant")
      | select([ .value.message.content[]? | select(.type == "tool_use" and .name == $name) ] | length > 0)
      | .key ]
    | first // empty
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# transcript_first_text_index <extended regex>
# 0-based index of the first assistant *text* block matching the regex; empty
# when nothing matches. Text blocks only, so a heading quoted inside a tool
# call's input does not count as having reported it.
transcript_first_text_index() {
  jq -s --arg re "$1" '
    [ to_entries[]
      | select(.value.type == "assistant")
      | select([ .value.message.content[]? | select(.type == "text") | .text | test($re) ] | any)
      | .key ]
    | first // empty
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# transcript_first_command_index <extended regex>
# 0-based index of the first Bash call whose command matches. Separate from
# transcript_first_tool_index because a case that legitimately runs its test
# command needs to ask about one kind of command, not about Bash as a whole.
transcript_first_command_index() {
  jq -s --arg re "$1" '
    [ to_entries[]
      | select(.value.type == "assistant")
      | select([ .value.message.content[]?
                 | select(.type == "tool_use" and .name == "Bash")
                 | .input.command | test($re) ] | any)
      | .key ]
    | first // empty
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# transcript_command_indexes <regex>
# Every record index whose Bash call matches, one per line, in order. For a
# case that places something between two commits -- create-pr after the first
# and before the last -- where the first match alone cannot say.
transcript_command_indexes() {
  jq -s -r --arg re "$1" '
    to_entries[]
    | select(.value.type == "assistant")
    | select([ .value.message.content[]?
               | select(.type == "tool_use" and .name == "Bash")
               | .input.command | test($re) ] | any)
    | .key
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# transcript_tool_uses_precede <tool name> <index>
# True when that tool was called at or before <index>. Written as a predicate
# so a case can pass it to `check` with the sense it wants.
transcript_tool_uses_precede() {
  local first
  first="$(transcript_first_tool_index "$1")"
  [ -n "$first" ] && [ "$first" -le "$2" ]
}

# transcript_skill_uses <skill name>
# How many times the Skill tool started that skill -- the measurement behind
# "did it start without being asked". The rounds below, counted: one rule for
# what is a call of the skill, so a count and a per-round check cannot disagree
# about it.
transcript_skill_uses() {
  transcript_skill_rounds "$1" | jq -s 'length'
}

# --- review rounds ---
#
# review-test and review-design rank findings P1/P2/P3 and share one loop: fix
# the P1 and P2 findings, review again in a fresh run, and stop once a round
# reports none. A count of Skill calls cannot tell that loop apart from a skill
# started twice for nothing, so these readers take each round apart.

# transcript_skill_rounds <skill name>
# One JSON object per line, one per call of the skill, in order. The input key
# of the Skill tool (skill, command, ...) changes between versions, so any
# string value in the input that equals the name, or "/<name>", is a call.
#   index        record index of the Skill call
#   brief        the input's strings other than the skill's name (its args)
#   result_index record index of the call's tool_result; null if none came back
#   report       that tool_result's text -- a forked skill's report, which the
#                caller has not necessarily written out
#   open         P1 and P2 items in the report (see below)
#   tool_calls   tool calls made inside the fork: records carrying the call's
#                id as parent_tool_use_id. The one measure of a round's weight
#                every transcript has
#   duration_ms, tokens
#                the tool_result record's tool_use_result.totalDurationMs /
#                .totalTokens, or null. Agent results carry them; whether a
#                forked Skill's does was not known when this was written, so
#                null means "not recorded", never zero
#
# `open` counts list items under a heading naming P1 or P2 ("### P1 (Critical)",
# "### P2"), skipping an item that says there is nothing ("なし", "None"). Both
# skills drop an empty priority section, so a clean round has no such heading
# at all; the skip is for a run that kept the heading anyway. Only an item that
# is nothing else is skipped: "テストなし" ("no test for ...") is how a P1 gap
# is naturally written, and skipping it would grade an open P1 as clean.
transcript_skill_rounds() {
  jq -sc --arg name "$1" '
    def open_findings:
      [ foreach split("\n")[] as $l ({sec: false, first: false, n: 0};
          if ($l | test("^#+")) then
            .sec = ($l | test("^#+\\s*P[12]([^0-9]|$)")) | .first = .sec
          elif ($l | test("^\\s*$")) then .
          # A section that opens by saying there is nothing has nothing open,
          # whatever it lists after -- a clean round lists what was resolved.
          elif .first and ($l | test("^\\s*([-*]\\s+)?(なし|該当なし|ありません|指摘なし|[Nn]one|[Nn]o findings|N/A)([。.:：、,]|\\s*$)")) then
            .sec = false | .first = false
          elif .sec and ($l | test("^\\s*([-*]|[0-9]+\\.)\\s+"))
            and ($l | test("^\\s*([-*]|[0-9]+\\.)\\s+(\\[ \\]\\s+)?(なし|該当なし|ありません|指摘なし|[Nn]one|[Nn]o findings|N/A)[。.]?\\s*$") | not) then
            .n += 1 | .first = false
          else .first = false end;
          .n) ] | last // 0;
    . as $all
    | [ to_entries[]
        | select(.value.type == "assistant")
        | .key as $i
        | .value.message.content[]?
        | select(.type == "tool_use" and .name == "Skill")
        | select([ .input // {} | .. | strings ] | any(. == $name or . == "/" + $name))
        | { index: $i,
            id: (.id // ""),
            brief: ([ .input // {} | .. | strings | select(. != $name and . != "/" + $name) ] | join("\n")) } ]
    | .[]
    | . as $r
    | ( [ $all
          | to_entries[]
          | select(.value.type == "user")
          | .key as $k
          | .value as $rec
          | .value.message.content
          | select(type == "array")
          | .[]
          | select(.type == "tool_result" and .tool_use_id == $r.id)
          | { index: $k, content: .content, meta: ($rec.tool_use_result // null) } ]
        | first ) as $res
    | ( if $res == null then ""
        elif ($res.content | type) == "string" then $res.content
        else [ $res.content[]? | select(.type == "text") | .text ] | join("\n") end ) as $report
    | { index: $r.index,
        brief: $r.brief,
        result_index: ($res.index // null),
        report: $report,
        open: ($report | open_findings),
        tool_calls: ([ $all[]
                       | select(.type == "assistant" and (.parent_tool_use_id // null) == $r.id)
                       | .message.content[]?
                       | select(.type == "tool_use") ] | length),
        duration_ms: ($res.meta.totalDurationMs? // null),
        tokens: ($res.meta.totalTokens? // null) }
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# transcript_caller_writes_between <from> <to>
# Write and Edit calls the caller made strictly between two record indices --
# the fix a re-run must follow. Calls inside a fork do not count: the skill
# writes nothing, and a write of its own is the boundary checks' business. A
# fix made through Bash (sed -i, a heredoc) is not seen; the review cases open
# no such command.
transcript_caller_writes_between() {
  jq -s --argjson a "$1" --argjson b "$2" '
    [ to_entries[]
      | select(.key > $a and .key < $b)
      | .value
      | select(.type == "assistant" and (.parent_tool_use_id // null) == null)
      | .message.content[]?
      | select(.type == "tool_use" and (.name == "Write" or .name == "Edit")) ]
    | length
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# review_loop_reran_only_after_findings <skill name>
# Every round after the first follows one that reported a P1 or P2. A re-run
# after a clean round, or a second start of the same review, is the waste "once
# per unit" exists to prevent. True with one round or none.
review_loop_reran_only_after_findings() {
  transcript_skill_rounds "$1" |
    jq -se '[ range(1; length) as $k | .[$k - 1].open > 0 ] | all' >/dev/null
}

# review_loop_fixed_before_each_rerun <skill name>
# Between the result of every round and the call of the next, the caller wrote
# something: a re-run with nothing fixed reviews the same thing again. A round
# whose result never came back counts as a failure here.
review_loop_fixed_before_each_rerun() {
  local rounds n k from to
  rounds="$(transcript_skill_rounds "$1")"
  n="$(jq -s 'length' <<<"$rounds")"
  for ((k = 1; k < n; k++)); do
    from="$(jq -s --argjson k "$k" '.[$k - 1].result_index // empty' <<<"$rounds")"
    to="$(jq -s --argjson k "$k" '.[$k].index' <<<"$rounds")"
    [ -n "$from" ] || return 1
    [ "$(transcript_caller_writes_between "$from" "$to")" -gt 0 ] || return 1
  done
}

# review_loop_ended_clean <skill name>
# The loop's stopping rule: the last round reported no P1 and no P2. False when
# the skill never ran, so a case must decide on its own whether it should have,
# and false when the last round's result never came back: a run cut off by its
# turn or budget limit mid-review has an empty report, which is not a clean one.
review_loop_ended_clean() {
  transcript_skill_rounds "$1" |
    jq -se 'length > 0 and last.result_index != null and last.open == 0' >/dev/null
}

# review_loop_rerun_checks <skill name>
# review_loop_checks <skill name>
# The predicates above as `check` lines. review_loop_rerun_checks asks what
# every re-run owes: a finding before it and a fix before it. A check about
# the rounds themselves -- a ceiling on how many, say -- belongs in
# review_loop_rerun_checks, so it reaches every case listed below as calling
# either bundle. review_loop_checks adds the stopping rule, a clean last round,
# for a case where one can be reached.
#
# Who calls what: the proactive cases (and their -with-claude-md variants)
# review_loop_checks; both *_check_loop in evals/grading.sh, for a case whose
# first round must find something, review_loop_checks plus their own;
# clean-unit-no-false-p1 review_loop_rerun_checks. Two cases run neither, so a
# new check here does not reach them unless added there:
# - well-tested-no-false-p1: nothing to find and no Write; it asks one thing
#   under a label of its own.
# - intended-layer-asks: its finding crosses the range and stays open in a run
#   nobody can answer, so it grades no loop at all -- although it can loop.
review_loop_rerun_checks() {
  check "fixed something before every re-run" \
    review_loop_fixed_before_each_rerun "$1"
  check "re-ran only after a round with P1 or P2" \
    review_loop_reran_only_after_findings "$1"
}

review_loop_checks() {
  review_loop_rerun_checks "$1"
  check "the last round reports no P1 and no P2" \
    review_loop_ended_clean "$1"
}

# --- grading with an LLM ---

SKILL_EVAL_JUDGE_SYSTEM_PROMPT='You grade text. Decide only whether the text under review satisfies the criterion, and answer with pass and a reason of one or two sentences. Whether the claims in the text are true is not your concern -- only whether the criterion is met.'
SKILL_EVAL_JUDGE_SCHEMA='{"type":"object","properties":{"pass":{"type":"boolean"},"reason":{"type":"string"}},"required":["pass","reason"]}'

# check_llm <label> <rubric> [<text>]
# Asks a toolless `claude -p` whether the text (the final response by default)
# satisfies the rubric. For contracts no regex can state -- "P1 names the
# missing error contract". The verdict wobbles, so keep deterministic contracts
# on the deterministic checks above and raise --runs when reading this one.
check_llm() {
  local label="$1" rubric="$2" text
  if [ $# -ge 3 ]; then
    text="$3"
  else
    text="$(transcript_result_text)"
  fi
  local claude_bin="${SKILL_EVAL_CLAUDE_BIN:-claude}"
  local judge_model="${SKILL_EVAL_JUDGE_MODEL:-haiku}"
  local verdict pass reason cost
  verdict="$(printf 'Criterion:\n%s\n\n--- text under review ---\n%s\n' "$rubric" "$text" |
    "$claude_bin" -p \
      --model "$judge_model" \
      --output-format json \
      --tools "" \
      --setting-sources "" \
      --strict-mcp-config \
      --no-session-persistence \
      --max-turns 1 \
      --max-budget-usd 0.1 \
      --system-prompt "$SKILL_EVAL_JUDGE_SYSTEM_PROMPT" \
      --json-schema "$SKILL_EVAL_JUDGE_SCHEMA" 2>/dev/null)" || verdict=""
  # `//` treats false as missing, so pass=false is matched explicitly rather
  # than falling through to "judge unavailable".
  pass="$(jq -r 'if .structured_output.pass == true then "true" elif .structured_output.pass == false then "false" else "" end' <<<"$verdict" 2>/dev/null || true)"
  reason="$(jq -r '.structured_output.reason // ""' <<<"$verdict" 2>/dev/null || true)"
  cost="$(jq -r '.total_cost_usd // 0' <<<"$verdict" 2>/dev/null || echo 0)"
  # The judge is a separate call, so its cost is absent from the skill's own
  # result record. The runner adds this file into the case total.
  if [ -n "${SKILL_EVAL_JUDGE_COST_FILE:-}" ]; then
    printf '%s\n' "$cost" >>"$SKILL_EVAL_JUDGE_COST_FILE"
  fi
  case "$pass" in
    true)
      printf 'PASS  %s (judge: %s)\n' "$label" "$reason"
      ;;
    false)
      printf 'FAIL  %s (judge: %s)\n' "$label" "$reason"
      SKILL_EVAL_FAILED=1
      ;;
    *)
      # An unreachable or malformed judge is a failure, not a pass. Treating it
      # as a pass is how a case stays green while measuring nothing.
      printf 'FAIL  %s (judge unavailable)\n' "$label"
      SKILL_EVAL_FAILED=1
      ;;
  esac
}

# Exit non-zero if anything failed. Call at the end of a case's assert.sh.
skill_eval_finish() {
  exit "$SKILL_EVAL_FAILED"
}
