#!/bin/bash
# Auto-approve commands whose multiline arguments prevent the allow-list
# wildcard "*" from matching (it does not match newline characters).
#
# Covered commands:
#   - git commit -m "..." (with optional -C <dir> or chained after git add)
#   - gh pr create --title ... --body "..."
#   - gh pr edit ... --body "..."
#
# See: https://github.com/anthropics/claude-code/issues/11932
# Docs: https://docs.claude.com/en/hooks

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# Only act on commands that contain newlines — single-line commands are
# already handled by the allow list.
[[ "$COMMAND" == *$'\n'* ]] || exit 0

approve() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: $reason
    }
  }'
}

first_line="${COMMAND%%$'\n'*}"

# git commit -m (with optional -C <dir> prefix or chained after git add)
if [[ "$first_line" =~ ^git\  ]] &&
   [[ "$COMMAND" =~ git\ (-C\ [^\ ]+\ )?commit\ -m\  ]]; then
  approve "Auto-approved multiline git commit via PreToolUse hook"
  exit 0
fi

# gh pr create --title ... --body ...
if [[ "$first_line" =~ ^gh\ pr\ create\  ]]; then
  approve "Auto-approved multiline gh pr create via PreToolUse hook"
  exit 0
fi

# gh pr edit ...
if [[ "$first_line" =~ ^gh\ pr\ edit ]]; then
  approve "Auto-approved multiline gh pr edit via PreToolUse hook"
  exit 0
fi
