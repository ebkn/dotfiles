#!/bin/bash
# Auto-approve commands whose multiline arguments prevent the allow-list
# wildcard "*" from matching (it does not match newline characters), so the
# commit / create-pr / update-pr skills can pass a message or PR body as data
# without a prompt for every commit.
#
# See: https://github.com/anthropics/claude-code/issues/11932
# Docs: https://docs.claude.com/en/hooks
#
# This hook is the only one here that emits "allow", so it is the only one whose
# bug widens permissions rather than narrowing them. Three rules keep that
# bounded, and all three exist because the first version had none of them:
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
    # matching the `git -C * ...` allow rules.
    while ((i < n)) && [[ "${argv[i]}" == -* ]]; do
      [[ "${argv[i]}" == "-C" ]] || return 1
      ((i + 1 < n)) || return 1
      i=$((i + 2))
    done
    ((i < n)) || return 1
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

# ---------------------------------------------------------------------------
# Scanner. Splits the command into segments the way the shell would, so the
# argv verified above is the argv that would run.
# ---------------------------------------------------------------------------

QSTATE=''          # '' outside quotes, otherwise the open quote character
CUR=''             # token being accumulated
HAVE_CUR=0         # CUR is a token even when empty (`git commit -m ''`)
TOKENS=()
PENDING_TAGS=()    # heredoc tags whose bodies start after this line
DATA_NEWLINE=0     # a newline landed inside a quoted argument or heredoc body
SEGMENTS=0

push_char() {
  CUR="$CUR$1"
  HAVE_CUR=1
}

push_run() {
  [[ -n "$1" ]] || return 0
  CUR="$CUR$1"
  HAVE_CUR=1
}

# Characters that end a run of ordinary literal text outside quotes. Used to
# skip whole runs at once: scanning a long commit message one `${line:i:1}` at
# a time costs O(n^2) and blew past the 5s hook timeout on a 1500-line message
# (25s measured), which shows up as a permission prompt with no explanation.
UNQ_SPECIAL='[[:space:]'\''"\\$`()<>#;&|]'

end_token() {
  if ((HAVE_CUR)); then
    TOKENS[${#TOKENS[@]}]=$CUR
    CUR=''
    HAVE_CUR=0
  fi
}

end_segment() {
  end_token
  if ((${#TOKENS[@]})); then
    segment_is_approved "${TOKENS[@]}" || exit 0
    SEGMENTS=$((SEGMENTS + 1))
  fi
  TOKENS=()
}

# Scan one physical line. Returns 1 for anything unparseable or expandable,
# which defers the whole command.
scan_line() {
  local line=$1
  local n=${#line}
  local i=0
  local c seg pre

  while ((i < n)); do
    seg=${line:i}

    # Single quotes: everything is literal, including $ and `, so the run ends
    # only at the closing quote.
    if [[ "$QSTATE" == "'" ]]; then
      pre=${seg%%\'*}
      if [[ "$pre" == "$seg" ]]; then
        push_run "$seg"
        return 0
      fi
      push_run "$pre"
      QSTATE=''
      i=$((i + ${#pre} + 1))
      continue
    fi

    if [[ "$QSTATE" == '"' ]]; then
      pre=${seg%%[\"\\\$\`]*}
      if [[ "$pre" == "$seg" ]]; then
        push_run "$seg"
        return 0
      fi
      push_run "$pre"
      i=$((i + ${#pre}))
      case "${line:i:1}" in
        '"') QSTATE=''; i=$((i + 1)) ;;
        '$' | '`') return 1 ;;        # the shell would expand it; argv unknown
        *)                            # backslash
          ((i + 1 < n)) || return 1   # line continuation: not worth parsing
          push_char "${line:i+1:1}"
          i=$((i + 2))
          ;;
      esac
      continue
    fi

    # Unquoted on purpose: UNQ_SPECIAL *is* the bracket pattern. Quoting it, as
    # SC2295 suggests, would look for that literal text instead.
    # shellcheck disable=SC2295
    pre=${seg%%$UNQ_SPECIAL*}
    if [[ "$pre" == "$seg" ]]; then
      push_run "$seg"
      return 0
    fi
    push_run "$pre"
    i=$((i + ${#pre}))
    c=${line:i:1}

    case "$c" in
      "'") QSTATE="'"; HAVE_CUR=1 ;;
      '"') QSTATE='"'; HAVE_CUR=1 ;;
      \\)
        ((i + 1 < n)) || return 1
        i=$((i + 1))
        push_char "${line:i:1}"
        ;;
      # Expansion and subshells make the real argv unknowable here.
      '$' | '`' | '(' | ')') return 1 ;;
      # Redirections could clobber a file; `<<` is handled below.
      '>') return 1 ;;
      '#')
        # A comment is the vector that defeated the first version of this hook,
        # and no commit or PR command needs one outside quoted data.
        if ((HAVE_CUR)); then push_char "$c"; else return 1; fi
        ;;
      '<')
        [[ "${line:i+1:1}" == '<' ]] || return 1        # plain input redirect
        local j=$((i + 2))
        [[ "${line:j:1}" == '<' ]] && return 1          # here-string
        [[ "${line:j:1}" == '-' ]] && j=$((j + 1))      # <<- (tab-stripped)
        while [[ "${line:j:1}" == ' ' || "${line:j:1}" == $'\t' ]]; do
          j=$((j + 1))
        done
        local q=${line:j:1}
        # The tag must be quoted. An unquoted tag makes the shell expand the
        # body, so a `$(...)` inside a commit message would execute.
        [[ "$q" == "'" || "$q" == '"' ]] || return 1
        j=$((j + 1))
        local tag=''
        while ((j < n)) && [[ "${line:j:1}" != "$q" ]]; do
          tag="$tag${line:j:1}"
          j=$((j + 1))
        done
        [[ "${line:j:1}" == "$q" ]] || return 1
        [[ -n "$tag" ]] || return 1
        end_token
        PENDING_TAGS[${#PENDING_TAGS[@]}]=$tag
        i=$j
        ;;
      ';') end_segment ;;
      '&')
        [[ "${line:i+1:1}" == '&' ]] && i=$((i + 1))
        end_segment
        ;;
      '|')
        [[ "${line:i+1:1}" == '|' ]] && i=$((i + 1))
        end_segment
        ;;
      ' ' | $'\t') end_token ;;
      # Unreachable: UNQ_SPECIAL and this case list are the same set, and every
      # ordinary character was consumed by the run above. If they ever drift,
      # defer rather than treat an unhandled metacharacter as literal text.
      *) return 1 ;;
    esac
    i=$((i + 1))
  done
  return 0
}

LINES=()
while IFS= read -r __line; do
  LINES[${#LINES[@]}]=$__line
done <<<"$COMMAND"

TOTAL=${#LINES[@]}
li=0
while ((li < TOTAL)); do
  scan_line "${LINES[li]}" || exit 0
  li=$((li + 1))

  # A newline inside a quoted argument is part of that argument -- exactly the
  # `-m "subject<newline><newline>body"` case this hook exists for.
  if [[ -n "$QSTATE" ]]; then
    push_char $'\n'
    DATA_NEWLINE=1
    continue
  fi

  end_token

  # Heredoc bodies belong to the line that opened them and are data, not
  # commands: `git commit -F - <<'EOF'` is the commit skill's documented form.
  if ((${#PENDING_TAGS[@]})); then
    for tag in "${PENDING_TAGS[@]}"; do
      found=0
      while ((li < TOTAL)); do
        body=${LINES[li]}
        li=$((li + 1))
        # Accepting a leading-whitespace terminator is looser than bash (which
        # requires an exact match unless `<<-`). That errs towards ending the
        # body early, so a real command is never mistaken for message text.
        if [[ "${body#"${body%%[![:space:]]*}"}" == "$tag" ]]; then
          found=1
          break
        fi
      done
      ((found)) || exit 0   # unterminated heredoc: unparseable
    done
    PENDING_TAGS=()
    DATA_NEWLINE=1
  fi

  end_segment
done

# An unterminated quote means the argv above is not what would run.
[[ -z "$QSTATE" ]] || exit 0
((${#PENDING_TAGS[@]} == 0)) || exit 0

end_segment

((SEGMENTS)) || exit 0

# Rule 3: without a newline in the data there is no wildcard to work around, so
# there is nothing for this hook to solve -- leave it to the normal flow.
((DATA_NEWLINE)) || exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "Every segment is an approved git/gh command and the newlines are message/body data (approve-multiline-commands)"
  }
}'
