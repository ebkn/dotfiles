#!/bin/bash
# Approve `git -C <dir> <rest>` when <dir> is inside the project and
# `git <rest>` is something the user's own allow rules already approve. It
# replaces the `Bash(git -C * <sub>*)` allow rules, whose `*` also matched any
# option inserted before the subcommand (`git -C . -c core.fsmonitor=<cmd>
# status`) -- Claude Code warns about exactly that rule shape -- and approved a
# -C into any repository on the machine, whose own .git/config can run a
# program on `git status`.
# See: https://code.claude.com/docs/en/errors (has a wildcard before the rest of
# the command).
#
# It emits "allow" only, so its bug widens permissions; four rules bound it:
#
#   1. Every segment of the command must be approved, as in
#      approve-multiline-commands.sh: "allow" approves the whole command.
#   2. The argv is the one segment-scan.lib.sh reads, which gives up on any
#      expansion, redirection, subshell or unterminated quote, so the argv
#      checked is the argv that runs.
#   3. The rules are read from the user's settings only. Project settings are
#      not used by Claude Code until its trust dialog is accepted; read here,
#      a cloned repository could approve its own commands.
#   4. A rule is used only when its one `*` is trailing. Matching is per argv
#      word and exact, so no rule matches more here than it would as written:
#      the words git receives are those of a command the rule approves.
#
# Silent on anything else, so a bug degrades to "you get asked". Claude Code
# still evaluates deny and ask rules after an "allow", and git-guard.sh's deny
# outranks it, so `git -C * push --force*` and friends keep their effect.
#
# Docs: https://code.claude.com/docs/en/hooks

set -euo pipefail

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
PROJECT=${CLAUDE_PROJECT_DIR:-}

[[ -n "$COMMAND" && -n "$CWD" && -n "$PROJECT" ]] || exit 0
# Without a -C there is nothing to add: the rules match such a command as is.
[[ "$COMMAND" == *-C* ]] || exit 0

SETTINGS="$HOME/.claude/settings.json"
[[ -f "$SETTINGS" ]] || exit 0

# Each usable rule as "<kind> <words>": exact, word (a trailing ` *` or `:*`,
# which also matches the bare words) or prefix (a trailing `*` glued to the
# last word).
rules=$(jq -r '
  .permissions.allow[]? | strings
  | select(test("^Bash\\(git [^*]*\\*?\\)$"))
  | ltrimstr("Bash(") | rtrimstr(")")
  | if endswith(" *") then "word " + rtrimstr(" *")
    elif endswith(":*") then "word " + rtrimstr(":*")
    elif endswith("*") then "prefix " + rtrimstr("*")
    else "exact " + . end
' "$SETTINGS" 2>/dev/null) || exit 0
[[ -n "$rules" ]] || exit 0

# shellcheck source=root/.claude/hooks/segment-scan.lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/segment-scan.lib.sh"
# shellcheck source=root/.claude/hooks/git-workdir.lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/git-workdir.lib.sh"

# $@: an argv. Returns 0 when some rule approves it.
rule_approves() {
  local line kind words w
  local -a rw
  while IFS= read -r line; do
    kind=${line%% *}
    words=${line#* }
    read -r -a rw <<<"$words"
    (($# >= ${#rw[@]})) || continue
    local k=0 ok=1 last=$((${#rw[@]} - 1)) argv=("$@")
    while ((k < ${#rw[@]})); do
      w=${rw[k]}
      if [[ "$kind" == prefix && $k -eq $last ]]; then
        [[ "${argv[k]}" == "$w"* ]] || ok=0
      else
        [[ "${argv[k]}" == "$w" ]] || ok=0
      fi
      k=$((k + 1))
    done
    ((ok)) || continue
    [[ "$kind" != exact || $# -eq ${#rw[@]} ]] || continue
    return 0
  done <<<"$rules"
  return 1
}

SAW_DASH_C=0

# $@: one segment's argv. Bare `git` only, as in approve-multiline-commands.sh:
# a path ending in /git may be any executable of that name.
segment_ok() {
  [[ "${1:-}" == git ]] || return 1
  local argv=("$@") n=$# i=1 dirs=() e
  # A word the shell expands is not the word read here: `git -C ~ status`
  # resolved literally finds a directory named `~` inside a project that ships
  # one, while the shell runs git in $HOME. Refused anywhere in the segment, as
  # the rule match compares words literally too.
  for e in "${SCAN_ARGV_EXPANDS[@]}"; do
    ((e == 0)) || return 1
  done
  while ((i < n)) && [[ "${argv[i]}" == "-C" ]]; do
    ((i + 1 < n)) || return 1
    dirs[${#dirs[@]}]=${argv[i + 1]}
    i=$((i + 2))
  done
  if ((${#dirs[@]})); then
    SAW_DASH_C=1
    git_workdir_in_project "$CWD" "$PROJECT" "${dirs[@]}" || return 1
  fi
  rule_approves git "${argv[@]:i}"
}

scan_command "$COMMAND" segment_ok || exit 0
((SCAN_SEGMENTS && SAW_DASH_C)) || exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "every segment is git whose -C stays inside the project and whose rest matches a user allow rule (git-dash-c-allow)"
  }
}'
