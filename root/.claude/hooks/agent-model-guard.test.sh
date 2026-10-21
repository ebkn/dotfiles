#!/bin/bash
# Exercises agent-model-guard.sh, the PreToolUse hook that refuses an Agent
# call naming no model.
#
# Both directions are silent: a guard that lets an unnamed model through puts
# the subagent on the session's model (Opus) with nothing to show for it, and a
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
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'
}

assert_eq "general-purpose with no model" deny \
  "$(decision '{"subagent_type":"general-purpose","prompt":"x","description":"d"}')"
assert_eq "no subagent_type and no model" deny \
  "$(decision '{"prompt":"x","description":"d"}')"
assert_eq "Explore with no model" deny \
  "$(decision '{"subagent_type":"Explore","prompt":"x","description":"d"}')"
assert_eq "empty model string" deny \
  "$(decision '{"subagent_type":"general-purpose","model":"","prompt":"x"}')"

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
assert_contains "reason asks for the model parameter" "$reason" "model"
assert_contains "reason offers the cheap tier" "$reason" "haiku"

test_summary
