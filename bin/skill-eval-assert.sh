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
# caller's shell (see the shell conventions in CLAUDE.md).
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
# "did it start without being asked". The input key of the Skill tool (skill,
# command, ...) changes between versions, so any string value in the input that
# equals the name counts as one use.
transcript_skill_uses() {
  jq -s --arg name "$1" '
    [ .[]
      | select(.type == "assistant")
      | .message.content[]?
      | select(.type == "tool_use" and .name == "Skill")
      | select([ .input // {} | .. | strings ] | any(. == $name or . == "/" + $name)) ]
    | length
  ' "$SKILL_EVAL_TRANSCRIPT"
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
  local model="${SKILL_EVAL_JUDGE_MODEL:-haiku}"
  local verdict pass reason cost
  verdict="$(printf 'Criterion:\n%s\n\n--- text under review ---\n%s\n' "$rubric" "$text" |
    "$claude_bin" -p \
      --model "$model" \
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
