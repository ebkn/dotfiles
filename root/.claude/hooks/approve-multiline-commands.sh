#!/bin/bash
# Auto-approve commands whose multiline arguments prevent the allow-list
# wildcard "*" from matching (it does not match newline characters), so the
# commit / create-pr / update-pr skills can pass a message or PR body as data
# without a prompt for every commit.
#
# See: https://github.com/anthropics/claude-code/issues/11932
# Docs: https://docs.claude.com/en/hooks
#
# This hook emits "allow", so its bug widens permissions rather than narrowing
# them (bin/test.md lists every hook that does). Three rules keep that bounded,
# and all three exist because the first version had none of them:
#
#   1. The command is parsed into segments and *every* segment must be an
#      approved git/gh invocation. The first version tested the whole command
#      string, so `git status<newline>rm -rf ~/x # git commit -m x` matched
#      ("first line starts with `git `" plus "`git commit -m ` appears
#      somewhere") and approved the `rm` along with it.
#   2. The command word is read positionally, per segment. "Appears somewhere in
#      the string" is what let a shell comment satisfy the check.
#   3. Newlines must be *data* -- inside a quoted argument or a heredoc body.
#      A command that is merely several statements on several lines has no
#      wildcard problem to solve and is left to the normal permission flow.
#
# Beyond newline handling this grants almost nothing new: `git add *`,
# `git commit -m *`, `git push`/`push origin HEAD`/`push -u origin HEAD`,
# `gh pr create *` and `gh pr edit*` are all already in permissions.allow. The
# single addition is `git commit -F`, the stdin-heredoc form the commit skill
# uses for multi-line messages.
#
# Fail-closed by design, like curl-guard.sh: anything unrecognised or
# unparseable emits no decision and falls through to the normal flow, so a bug
# here degrades to "you get asked", never to "it runs". Nothing this hook emits
# can override permissions.deny or permissions.ask, so `rm`, `curl` and the rest
# keep their prompts regardless; what an over-approval really costs is the auto
# mode classifier's judgement on segments no rule covers (`bash /tmp/x.sh`,
# `python -c ...`, `ssh ...`).
#
# Written for bash 3.2 (/bin/bash on macOS): no mapfile, no empty-array
# expansion under `set -u`.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
# For a git -C only; empty, every -C is refused (git_dash_c_in_project).
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
PROJECT=${CLAUDE_PROJECT_DIR:-}

[[ -n "$COMMAND" ]] || exit 0

# Only act on commands that contain newlines -- single-line commands are
# already handled by the allow list.
[[ "$COMMAND" == *$'\n'* ]] || exit 0

# ---------------------------------------------------------------------------
# Safelist: what a single segment is allowed to be.
# ---------------------------------------------------------------------------

# `git commit` options that carry the message. Everything else about commit --
# --amend, --author, -a -- is deliberately absent: it is not what this hook
# exists for, and omitting it costs a prompt, not a failure.
commit_opt_takes_value() {
  case "$1" in
    -m | --message | -F | --file) return 0 ;;
  esac
  return 1
}

commit_opt_is_inline() {
  # `-mfoo`, `--message=foo`, `-F-`: the value is fused to the option.
  case "$1" in
    -m?* | -F?* | --message=* | --file=*) return 0 ;;
  esac
  return 1
}

# $@ is one segment's argv. Returns 0 only when the whole segment is approved.
segment_is_approved() {
  (($#)) || return 1

  local argv=("$@")
  local n=$#
  local i cmd sub

  # Bare names only, resolved through $PATH, which is trusted. A `*/git` glob
  # here would read as "tolerate /usr/bin/git" but actually match *any* path
  # ending in /git -- `./evil/git`, `scripts/gh` -- so a repo that merely ships
  # an executable with the right basename gets approved with no prompt. Note
  # the asymmetry with git-guard.sh, which matches `*/git` on purpose: a hook
  # that denies must match broadly, one that approves must match narrowly.
  case "${argv[0]}" in
    git) cmd=git ;;
    gh) cmd=gh ;;
    *) return 1 ;;
  esac

  i=1

  if [[ "$cmd" == git ]]; then
    # Options before the subcommand can make git run a program of the caller's
    # choosing (-c core.fsmonitor=..., --exec-path, --git-dir into a repo with
    # hooks -- see git-guard.sh). `-C <dir>` is the only one accepted here,
    # and only into the project: the same check git-dash-c-allow.sh makes, so
    # the two cannot disagree. A -C elsewhere reaches a repository whose own
    # .git/config can run a program on `git commit`.
    git_dash_c_in_project "$CWD" "$PROJECT" "${argv[@]}" || return 1
    i=$GIT_DASH_C_NEXT
    ((i < n)) || return 1
    [[ "${argv[i]}" != -* ]] || return 1
    sub=${argv[i]}
    i=$((i + 1))

    case "$sub" in
      add)
        # `git add *` is already allow-listed and cannot execute anything.
        return 0
        ;;
      commit)
        local saw_message=0
        while ((i < n)); do
          local tok=${argv[i]}
          if [[ "$tok" == "--" ]]; then
            # Everything after is a pathspec.
            return $((1 - saw_message))
          fi
          if [[ "$tok" == -* ]]; then
            if commit_opt_is_inline "$tok"; then
              saw_message=1
              i=$((i + 1))
              continue
            fi
            commit_opt_takes_value "$tok" || return 1
            # Consume the value unconditionally: a message may itself look like
            # an option (`git commit -m -x`).
            ((i + 1 < n)) || return 1
            saw_message=1
            i=$((i + 2))
            continue
          fi
          # A pathspec. Harmless, but it must not be an unconsumed option value.
          i=$((i + 1))
        done
        ((saw_message)) || return 1
        return 0
        ;;
      push)
        # Exactly the three forms permissions.allow already grants.
        local rest="${argv[*]:i}"
        case "$rest" in
          "" | "origin HEAD" | "-u origin HEAD") return 0 ;;
        esac
        return 1
        ;;
    esac
    return 1
  fi

  # gh: only `gh pr create` and `gh pr edit`, both already allow-listed with a
  # trailing wildcard, so their arguments need no further narrowing here.
  ((i + 1 < n)) || return 1
  [[ "${argv[i]}" == "pr" ]] || return 1
  case "${argv[i + 1]}" in
    create | edit) return 0 ;;
  esac
  return 1
}

# The scanner splits the command into segments the way the shell would, so the
# argv verified above is the argv that would run. git-dash-c-allow.sh needs
# the same argv and sources it too.
# shellcheck source=root/.claude/hooks/segment-scan.lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/segment-scan.lib.sh"
# shellcheck source=root/.claude/hooks/git-workdir.lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/git-workdir.lib.sh"

scan_command "$COMMAND" segment_is_approved || exit 0
((SCAN_SEGMENTS)) || exit 0

# Rule 3: without a newline in the data there is no wildcard to work around, so
# there is nothing for this hook to solve -- leave it to the normal flow.
((SCAN_DATA_NEWLINE)) || exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "Every segment is an approved git/gh command and the newlines are message/body data (approve-multiline-commands)"
  }
}'
