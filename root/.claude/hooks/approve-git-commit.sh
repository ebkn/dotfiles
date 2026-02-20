#!/bin/bash
# Auto-approve "git commit -m" commands that contain newlines.
#
# The allow rule "Bash(git commit -m *)" doesn't match when the
# message includes literal newlines because the wildcard "*" does
# not match newline characters. This PreToolUse hook fills the gap.
#
# See: https://github.com/anthropics/claude-code/issues/11932
# Docs: https://docs.claude.com/en/hooks

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# Approve if:
#   1. The first line starts with "git " (rejects non-git prefixes)
#   2. The command contains "git commit -m " (with optional -C <dir>)
# Covers: git commit -m ...
#         git add ... && git commit -m ...
#         git -C <dir> add ... && git -C <dir> commit -m ...
first_line="${COMMAND%%$'\n'*}"
if [[ "$first_line" =~ ^git\  ]] &&
   [[ "$COMMAND" =~ git\ (-C\ [^\ ]+\ )?commit\ -m\  ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: "Auto-approved git commit via PreToolUse hook"
    }
  }'
fi
