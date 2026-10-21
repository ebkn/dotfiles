#!/bin/bash
# Refuse an Agent call that names no `model`, so every subagent runs on a tier
# chosen for its task rather than on whatever the session runs.
#
# Why a refusal and not a rewrite: an omitted model falls through to the
# session's model (Opus here, in fast mode), and the instruction to pick one in
# CLAUDE.md loses to Claude Code's own guidance, which tells workflow authors to
# omit it. A hook that filled in a fixed model would only move the default; the
# deny reason goes back to the model, which then makes the choice itself.
# The default for whatever still gets past this -- workflow agent() calls are
# not documented to reach PreToolUse -- is CLAUDE_CODE_SUBAGENT_MODEL in
# settings.json.
#
# Fails open: a missing jq or bad input exits non-zero without blocking, which
# costs tokens, never a spawn.
#
# Docs: https://code.claude.com/docs/en/sub-agents#choose-a-model
#       https://code.claude.com/docs/en/hooks (PreToolUse, Agent tool_input)

set -eo pipefail

INPUT=$(cat)
# jq reads empty input as no value, not an error, so without this an empty
# stdin would look like a call with no model and be refused.
[[ -n "$INPUT" ]] || exit 1
MODEL=$(printf '%s' "$INPUT" | jq -r '.tool_input.model // empty')
TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty')

[[ -z "$MODEL" ]] || exit 0

# These ignore a per-call model or already run on a cheap one, so refusing them
# would cost a round-trip and change nothing: a fork always takes the parent's
# model; claude-code-guide runs on Haiku and statusline-setup on Sonnet.
case "$TYPE" in
  fork | claude-code-guide | statusline-setup) exit 0 ;;
esac

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Pass `model` explicitly on every Agent call (agent-model-guard). Choose the cheapest tier that can do this task well: haiku for mechanical lookups, grep-and-report sweeps and summaries; sonnet for ordinary code reading, research and implementation; opus only for hard reasoning such as design judgement, subtle bugs or adversarial verification. Retry the same call with `model` set."
  }
}'
