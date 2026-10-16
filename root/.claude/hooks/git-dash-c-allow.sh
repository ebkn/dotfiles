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
#   2. The argv is the one segment-scan.lib.sh reads. It gives up where the
#      argv cannot be known (`$`, a backtick, a redirection, a subshell, an
#      unterminated quote), and marks a word the shell would still rewrite (`~`,
#      a glob, a brace) in SCAN_ARGV_EXPANDS, which this hook refuses -- so the
#      argv checked is the argv that runs. Dropping that refusal because "the
#      scanner gives up on expansions" would approve `git -C ~ status`.
#   3. The rules are read from the user's settings only. Project settings are
#      not used by Claude Code until its trust dialog is accepted; read here,
#      a cloned repository could approve its own commands.
#   4. A rule is used only when its one `*` is trailing. Matching is per argv
#      word and exact, so no rule matches more here than it would as written:
#      the words git receives are those of a command the rule approves.
#
# Silent on anything else, so a bug degrades to "you get asked". That includes
# a `git <rest>` a deny or ask rule of any settings layer covers: Claude Code
# applies those rules after an "allow", but to the command as written, so
# `Bash(git branch -D *)` never sees `git -C x branch -D y`. git-guard.sh
# applies them to the -C form; staying silent here as well means the result
# does not hang on how the two hooks' decisions combine (git-rules.lib.sh).
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
# shellcheck source=root/.claude/hooks/git-rules.lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/git-rules.lib.sh"

REFUSING=$(
  git_rule_patterns deny
  git_rule_patterns ask
)

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
  local argv=("$@") e
  # A word the shell expands is not the word read here. git_dash_c_in_project
  # refuses one as a -C path; here it is refused anywhere in the segment, as
  # the rule match compares words literally too.
  for e in "${SCAN_ARGV_EXPANDS[@]}"; do
    ((e == 0)) || return 1
  done
  git_dash_c_in_project "$CWD" "$PROJECT" "$@" || return 1
  ((GIT_DASH_C_SEEN == 0)) || SAW_DASH_C=1
  rule_approves git "${argv[@]:GIT_DASH_C_NEXT}" || return 1
  # The deny and ask rules are matched from the subcommand on, as git-guard.sh
  # matches them: an option such as --no-pager between -C and the subcommand
  # would otherwise keep `git branch -D *` from seeing the rest.
  local i=$GIT_DASH_C_NEXT
  while ((i < ${#argv[@]})) && [[ "${argv[i]}" == -* ]]; do
    i=$((i + 1))
  done
  ! git_rule_match "$REFUSING" git "${argv[@]:i}"
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
