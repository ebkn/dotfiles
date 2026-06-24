#!/bin/bash
# Strip a redundant leading `cd <dir> && ...` (or `cd <dir>; ...`) when <dir>
# resolves to the session's current working directory.
#
# Why this exists:
#   The agent often defensively prepends `cd <worktree-root> &&` even though
#   Claude Code is already launched from that worktree root. The wrapping cd is
#   pure noise, but it (a) is not in the allow list and (b) turns the call into
#   a compound command, so it forces a permission prompt on every invocation.
#   Measured across this repo's transcripts, redundant `cd` jumped ~12x as the
#   git-worktree workflow took over (May -> June 2026).
#
# What it does NOT do:
#   It does not blanket-approve the command. It rewrites the input to drop only
#   the redundant cd, then returns `defer` so the *remaining* command still goes
#   through the normal allow/ask/deny evaluation. A risky trailing command
#   (e.g. `curl`, `rm`) is therefore still subject to its usual prompt.
#
# Only literal, static cd targets are handled. Targets containing command
# substitution, variables, or globs are left untouched (safer to defer).
#
# Docs: https://code.claude.com/docs/en/hooks (PreToolUse updatedInput)

set -uo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

[ -n "$COMMAND" ] || exit 0
[ -n "$CWD" ] || exit 0

# Must start with a `cd ` to be a candidate.
case "$COMMAND" in
  cd\ *) ;;
  *) exit 0 ;;
esac

# Pick the earliest separator between `&&` and `;`.
before_amp="${COMMAND%%&&*}"
before_semi="${COMMAND%%;*}"
if [ "$before_amp" = "$COMMAND" ] && [ "$before_semi" = "$COMMAND" ]; then
  exit 0 # no separator -> standalone cd, nothing to strip
fi
if [ "${#before_amp}" -le "${#before_semi}" ]; then
  prefix="$before_amp"
  rest="${COMMAND#*&&}"
else
  prefix="$before_semi"
  rest="${COMMAND#*;}"
fi

# prefix must be exactly `cd <target>` (with surrounding whitespace allowed).
case "$prefix" in
  cd\ *) ;;
  *) exit 0 ;;
esac

target="${prefix#cd }"
# trim leading/trailing whitespace
target="${target#"${target%%[![:space:]]*}"}"
target="${target%"${target##*[![:space:]]}"}"

# strip a single layer of surrounding quotes
case "$target" in
  \"*\") target="${target#\"}"; target="${target%\"}" ;;
  \'*\') target="${target#\'}"; target="${target%\'}" ;;
esac

# Refuse dynamic / non-literal targets — defer to normal flow.
case "$target" in
  ''|*'$'*|*'`'*|*'*'*|*'?'*|*'['*|'~'*) exit 0 ;;
esac

# Resolve target to an absolute, normalized path.
case "$target" in
  /*) abs="$target" ;;
  *)  abs="$CWD/$target" ;;
esac
rp_target="$(cd "$abs" 2>/dev/null && pwd -P)" || exit 0
rp_cwd="$(cd "$CWD" 2>/dev/null && pwd -P)" || exit 0
[ -n "$rp_target" ] && [ "$rp_target" = "$rp_cwd" ] || exit 0

# Strip the redundant cd; re-evaluate the remainder normally.
newcmd="${rest#"${rest%%[![:space:]]*}"}"
[ -n "$newcmd" ] || exit 0

jq -n --arg cmd "$newcmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "defer",
    permissionDecisionReason: "Stripped redundant leading cd (target equals cwd); re-evaluating the remaining command through the normal permission flow.",
    updatedInput: { command: $cmd }
  }
}'
exit 0
