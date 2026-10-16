# shellcheck shell=bash
# Shell segment scanner for the hooks that emit "allow". Sourced, so it sets no
# shell options and has no shebang (bin/lint-shell names it explicitly).
#
#   scan_command <command> <predicate>
#
# Splits <command> into its simple commands the way the shell would and calls
# <predicate> with each one's argv. Returns 0 only when the whole command parsed
# and every segment was approved; afterwards SCAN_SEGMENTS holds how many there
# were and SCAN_DATA_NEWLINE whether a newline sat inside a quoted argument or a
# heredoc body rather than between statements.
#
# It errs toward "cannot tell", which is the right direction for an allow hook
# only: anything it does not model -- an expansion (`$`, backtick, an unquoted
# heredoc tag), a subshell, a redirection, a comment outside quoted data, an
# unterminated quote or heredoc -- returns 1, and the caller emits no decision.
# git-guard.sh has a parser of its own on purpose, resolved the other way, and
# neither may be swapped for the other.
#
# Written for bash 3.2 (/bin/bash on macOS): no mapfile, no empty-array
# expansion under `set -u`.

SCAN_QSTATE=''  # '' outside quotes, otherwise the open quote character
SCAN_CUR=''     # token being accumulated
SCAN_HAVE_CUR=0 # SCAN_CUR is a token even when empty (`git commit -m ''`)
SCAN_TOKENS=()
SCAN_PENDING_TAGS=() # heredoc tags whose bodies start after this line
SCAN_DATA_NEWLINE=0
SCAN_SEGMENTS=0
SCAN_PREDICATE=''

scan_push_run() {
  [[ -n "$1" ]] || return 0
  SCAN_CUR="$SCAN_CUR$1"
  SCAN_HAVE_CUR=1
}

# Characters that end a run of ordinary literal text outside quotes. Used to
# skip whole runs at once: scanning a long commit message one `${line:i:1}` at
# a time costs O(n^2) and blew past the 5s hook timeout on a 1500-line message
# (25s measured), which shows up as a permission prompt with no explanation.
SCAN_UNQ_SPECIAL='[[:space:]'\''"\\$`()<>#;&|]'

scan_end_token() {
  if ((SCAN_HAVE_CUR)); then
    SCAN_TOKENS[${#SCAN_TOKENS[@]}]=$SCAN_CUR
    SCAN_CUR=''
    SCAN_HAVE_CUR=0
  fi
}

scan_end_segment() {
  scan_end_token
  if ((${#SCAN_TOKENS[@]})); then
    "$SCAN_PREDICATE" "${SCAN_TOKENS[@]}" || return 1
    SCAN_SEGMENTS=$((SCAN_SEGMENTS + 1))
  fi
  SCAN_TOKENS=()
}

# Scan one physical line. Returns 1 for anything unparseable or expandable, or
# a segment the predicate rejected.
scan_line() {
  local line=$1
  local n=${#line}
  local i=0
  local c seg pre

  while ((i < n)); do
    seg=${line:i}

    # Single quotes: everything is literal, including $ and `, so the run ends
    # only at the closing quote.
    if [[ "$SCAN_QSTATE" == "'" ]]; then
      pre=${seg%%\'*}
      if [[ "$pre" == "$seg" ]]; then
        scan_push_run "$seg"
        return 0
      fi
      scan_push_run "$pre"
      SCAN_QSTATE=''
      i=$((i + ${#pre} + 1))
      continue
    fi

    if [[ "$SCAN_QSTATE" == '"' ]]; then
      pre=${seg%%[\"\\\$\`]*}
      if [[ "$pre" == "$seg" ]]; then
        scan_push_run "$seg"
        return 0
      fi
      scan_push_run "$pre"
      i=$((i + ${#pre}))
      case "${line:i:1}" in
        '"')
          SCAN_QSTATE=''
          i=$((i + 1))
          ;;
        '$' | '`') return 1 ;;      # the shell would expand it; argv unknown
        *)                          # backslash
          ((i + 1 < n)) || return 1 # line continuation: not worth parsing
          scan_push_run "${line:i+1:1}"
          i=$((i + 2))
          ;;
      esac
      continue
    fi

    # Unquoted on purpose: SCAN_UNQ_SPECIAL *is* the bracket pattern. Quoting
    # it, as SC2295 suggests, would look for that literal text instead.
    # shellcheck disable=SC2295
    pre=${seg%%$SCAN_UNQ_SPECIAL*}
    if [[ "$pre" == "$seg" ]]; then
      scan_push_run "$seg"
      return 0
    fi
    scan_push_run "$pre"
    i=$((i + ${#pre}))
    c=${line:i:1}

    case "$c" in
      "'")
        SCAN_QSTATE="'"
        SCAN_HAVE_CUR=1
        ;;
      '"')
        SCAN_QSTATE='"'
        SCAN_HAVE_CUR=1
        ;;
      \\)
        ((i + 1 < n)) || return 1
        i=$((i + 1))
        scan_push_run "${line:i:1}"
        ;;
      # Expansion and subshells make the real argv unknowable here.
      '$' | '`' | '(' | ')') return 1 ;;
      # Redirections could clobber a file; `<<` is handled below.
      '>') return 1 ;;
      '#')
        # A comment is the vector that defeated the first version of
        # approve-multiline-commands.sh, and no command these hooks approve
        # needs one outside quoted data.
        if ((SCAN_HAVE_CUR)); then scan_push_run "$c"; else return 1; fi
        ;;
      '<')
        [[ "${line:i+1:1}" == '<' ]] || return 1 # plain input redirect
        local j=$((i + 2))
        [[ "${line:j:1}" == '<' ]] && return 1     # here-string
        [[ "${line:j:1}" == '-' ]] && j=$((j + 1)) # <<- (tab-stripped)
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
        scan_end_token
        SCAN_PENDING_TAGS[${#SCAN_PENDING_TAGS[@]}]=$tag
        i=$j
        ;;
      ';') scan_end_segment || return 1 ;;
      '&')
        [[ "${line:i+1:1}" == '&' ]] && i=$((i + 1))
        scan_end_segment || return 1
        ;;
      '|')
        [[ "${line:i+1:1}" == '|' ]] && i=$((i + 1))
        scan_end_segment || return 1
        ;;
      ' ' | $'\t') scan_end_token ;;
      # Unreachable: SCAN_UNQ_SPECIAL and this case list are the same set, and
      # every ordinary character was consumed by the run above. If they ever
      # drift, defer rather than treat an unhandled metacharacter as literal.
      *) return 1 ;;
    esac
    i=$((i + 1))
  done
  return 0
}

scan_command() {
  SCAN_PREDICATE=$2
  SCAN_QSTATE='' SCAN_CUR='' SCAN_HAVE_CUR=0 SCAN_DATA_NEWLINE=0 SCAN_SEGMENTS=0
  SCAN_TOKENS=()
  SCAN_PENDING_TAGS=()

  local lines=() line total li tag body found
  while IFS= read -r line; do
    lines[${#lines[@]}]=$line
  done <<<"$1"

  total=${#lines[@]}
  li=0
  while ((li < total)); do
    scan_line "${lines[li]}" || return 1
    li=$((li + 1))

    # A newline inside a quoted argument is part of that argument -- the
    # `-m "subject<newline><newline>body"` case.
    if [[ -n "$SCAN_QSTATE" ]]; then
      scan_push_run $'\n'
      SCAN_DATA_NEWLINE=1
      continue
    fi

    scan_end_token

    # Heredoc bodies belong to the line that opened them and are data, not
    # commands: `git commit -F - <<'EOF'` is the commit skill's documented form.
    if ((${#SCAN_PENDING_TAGS[@]})); then
      for tag in "${SCAN_PENDING_TAGS[@]}"; do
        found=0
        while ((li < total)); do
          body=${lines[li]}
          li=$((li + 1))
          # Accepting a leading-whitespace terminator is looser than bash (which
          # requires an exact match unless `<<-`). That errs towards ending the
          # body early, so a real command is never mistaken for message text.
          if [[ "${body#"${body%%[![:space:]]*}"}" == "$tag" ]]; then
            found=1
            break
          fi
        done
        ((found)) || return 1 # unterminated heredoc: unparseable
      done
      SCAN_PENDING_TAGS=()
      # shellcheck disable=SC2034 # an output, read by the sourcing hook
      SCAN_DATA_NEWLINE=1
    fi

    scan_end_segment || return 1
  done

  # An unterminated quote means the argv above is not what would run.
  [[ -z "$SCAN_QSTATE" ]] || return 1
  ((${#SCAN_PENDING_TAGS[@]} == 0)) || return 1

  scan_end_segment || return 1
  return 0
}
