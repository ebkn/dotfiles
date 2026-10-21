#!/bin/bash
# Exercises agent-model-guard.sh, the PreToolUse hook that refuses an Agent
# call naming no model.
#
# Both directions are silent: a guard that lets an unnamed model through puts
# the subagent on a default nobody chose for the task (which one: the hook's
# header), and a
# guard that refuses a call it should pass blocks the spawn outright. So each
# case asserts the decision Claude Code would read -- a deny with a reason, or
# no output at all -- not the exit status, which is 0 either way.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-model-guard.sh"
# shellcheck source=bin/test-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../../bin/test-lib.sh" || exit 2

# decision <tool_input-json> -- the permissionDecision the hook emits, `none`
# when it prints nothing, or `exit<N>` when it fails.
decision() {
  local out status
  if out=$(jq -n --argjson i "$1" '{tool_name:"Agent", tool_input:$i}' | "$HOOK"); then status=0; else status=$?; fi
  if [ "$status" -ne 0 ]; then
    printf 'exit%s' "$status"
    return
  fi
  if [ -z "$out" ]; then
    printf none
    return
  fi
  # Claude Code ignores a hookSpecificOutput for another event, so a deny that
  # lost its hookEventName would refuse nothing.
  printf '%s' "$out" | jq -r '.hookSpecificOutput |
    if .hookEventName == "PreToolUse" then .permissionDecision else "wrong-event" end'
}

# raw <stdin> [<PATH>] -- the hook's exit status and output for raw input.
raw() {
  local out status
  if out=$(printf '%s' "$1" | PATH=${2:-$PATH} "$HOOK" 2>/dev/null); then status=0; else status=$?; fi
  printf 'exit%s:%s' "$status" "$out"
}

assert_eq "general-purpose with no model" deny \
  "$(decision '{"subagent_type":"general-purpose","prompt":"x","description":"d"}')"
assert_eq "no subagent_type and no model" deny \
  "$(decision '{"prompt":"x","description":"d"}')"
assert_eq "Explore with no model" deny \
  "$(decision '{"subagent_type":"Explore","prompt":"x","description":"d"}')"
assert_eq "empty model string" deny \
  "$(decision '{"subagent_type":"general-purpose","model":"","prompt":"x"}')"
assert_eq "null model" deny \
  "$(decision '{"subagent_type":"general-purpose","model":null,"prompt":"x"}')"

# The exemption is an exact name: a glob or a case-folded match would let any
# lookalike type spawn on a default nobody chose.
for t in Fork fork-something my-claude-code-guide; do
  assert_eq "lookalike subagent_type $t with no model" deny \
    "$(decision "$(jq -nc --arg t "$t" '{subagent_type:$t, prompt:"x"}')")"
done

for m in haiku sonnet opus fable claude-sonnet-5-5; do
  assert_eq "model $m" none \
    "$(decision "$(jq -nc --arg m "$m" '{subagent_type:"general-purpose", model:$m, prompt:"x"}')")"
done

# These run on a model of their own whatever the call says: a fork always on
# the parent's, the two built-ins on a fixed cheap one. Refusing them would cost
# a round-trip and change nothing.
for t in fork claude-code-guide statusline-setup; do
  assert_eq "subagent_type $t with no model" none \
    "$(decision "$(jq -nc --arg t "$t" '{subagent_type:$t, prompt:"x"}')")"
done

# The reason is all the model sees of the refusal, so it must say what to do.
reason=$(jq -n '{tool_name:"Agent", tool_input:{subagent_type:"general-purpose",prompt:"x"}}' |
  "$HOOK" | jq -r '.hookSpecificOutput.permissionDecisionReason')
assert_contains "reason asks for a retry with model set" "$reason" "Retry the same call with"
assert_contains "reason offers the cheap tier" "$reason" "haiku"

# Fail open: input the hook cannot read must not turn into a refusal. A
# PreToolUse hook exiting non-zero other than 2 lets the call through; exit 2
# or a printed deny would block it.
for input in '' 'not json'; do
  got=$(raw "$input")
  assert_not_contains "input '$input' does not deny" "$got" '"deny"'
  assert_not_contains "input '$input' does not exit 2" "$got" 'exit2:'
  assert_not_contains "input '$input' does not exit 0" "$got" 'exit0:'
done
# No jq on PATH, but cat still there: the hook reads stdin with cat first, so a
# PATH with nothing on it would fail on cat and never reach the jq call.
test_tmpdir
ln -s "$(command -v cat)" "$TEST_TMPDIR/cat"
assert_eq "the no-jq PATH has cat but no jq" "$TEST_TMPDIR/cat:" \
  "$(PATH=$TEST_TMPDIR command -v cat):$(PATH=$TEST_TMPDIR command -v jq)"
got=$(raw '{"tool_input":{"subagent_type":"general-purpose"}}' "$TEST_TMPDIR")
assert_not_contains "no jq does not deny" "$got" '"deny"'
assert_not_contains "no jq does not exit 2" "$got" 'exit2:'
assert_not_contains "no jq does not exit 0" "$got" 'exit0:'

test_summary
