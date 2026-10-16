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
# The predicate runs inside the scanner's own functions, and bash scope is
# dynamic: a predicate variable not declared `local` writes into whatever the
# scanner has of that name. Undeclared `line` in git-dash-c-allow.sh replaced
# the line being scanned, dropped `; rm -rf x` unread, and the command was
# approved. So every scanner name is prefixed (_sl_, _sc_, SCAN_), and
# segment-scan.lib.test.sh drives a predicate that clobbers the common ones.
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
  local _sl_line=$1
  local _sl_n=${#_sl_line}
  local _sl_i=0
  local _sl_c _sl_seg _sl_pre

  while ((_sl_i < _sl_n)); do
    _sl_seg=${_sl_line:_sl_i}

    # Single quotes: everything is literal, including $ and `, so the run ends
    # only at the closing quote.
    if [[ "$SCAN_QSTATE" == "'" ]]; then
      _sl_pre=${_sl_seg%%\'*}
      if [[ "$_sl_pre" == "$_sl_seg" ]]; then
        scan_push_run "$_sl_seg"
        return 0
      fi
      scan_push_run "$_sl_pre"
      SCAN_QSTATE=''
      _sl_i=$((_sl_i + ${#_sl_pre} + 1))
      continue
    fi

    if [[ "$SCAN_QSTATE" == '"' ]]; then
      _sl_pre=${_sl_seg%%[\"\\\$\`]*}
      if [[ "$_sl_pre" == "$_sl_seg" ]]; then
        scan_push_run "$_sl_seg"
        return 0
      fi
      scan_push_run "$_sl_pre"
      _sl_i=$((_sl_i + ${#_sl_pre}))
      case "${_sl_line:_sl_i:1}" in
        '"')
          SCAN_QSTATE=''
          _sl_i=$((_sl_i + 1))
          ;;
        '$' | '`') return 1 ;;              # the shell would expand it; argv unknown
        *)                                  # backslash
          ((_sl_i + 1 < _sl_n)) || return 1 # line continuation: not worth parsing
          scan_push_run "${_sl_line:_sl_i+1:1}"
          _sl_i=$((_sl_i + 2))
          ;;
      esac
      continue
    fi

    # Unquoted on purpose: SCAN_UNQ_SPECIAL *is* the bracket pattern. Quoting
    # it, as SC2295 suggests, would look for that literal text instead.
    # shellcheck disable=SC2295
    _sl_pre=${_sl_seg%%$SCAN_UNQ_SPECIAL*}
    if [[ "$_sl_pre" == "$_sl_seg" ]]; then
      scan_push_run "$_sl_seg"
      return 0
    fi
    scan_push_run "$_sl_pre"
    _sl_i=$((_sl_i + ${#_sl_pre}))
    _sl_c=${_sl_line:_sl_i:1}

    case "$_sl_c" in
      "'")
        SCAN_QSTATE="'"
        SCAN_HAVE_CUR=1
        ;;
      '"')
        SCAN_QSTATE='"'
        SCAN_HAVE_CUR=1
        ;;
      \\)
        ((_sl_i + 1 < _sl_n)) || return 1
        _sl_i=$((_sl_i + 1))
        scan_push_run "${_sl_line:_sl_i:1}"
        ;;
      # Expansion and subshells make the real argv unknowable here.
      '$' | '`' | '(' | ')') return 1 ;;
      # Redirections could clobber a file; `<<` is handled below.
      '>') return 1 ;;
      '#')
        # A comment is the vector that defeated the first version of
        # approve-multiline-commands.sh, and no command these hooks approve
        # needs one outside quoted data.
        if ((SCAN_HAVE_CUR)); then scan_push_run "$_sl_c"; else return 1; fi
        ;;
      '<')
        [[ "${_sl_line:_sl_i+1:1}" == '<' ]] || return 1 # plain input redirect
        local _sl_j=$((_sl_i + 2))
        [[ "${_sl_line:_sl_j:1}" == '<' ]] && return 1             # here-string
        [[ "${_sl_line:_sl_j:1}" == '-' ]] && _sl_j=$((_sl_j + 1)) # <<- (tab-stripped)
        while [[ "${_sl_line:_sl_j:1}" == ' ' || "${_sl_line:_sl_j:1}" == $'\t' ]]; do
          _sl_j=$((_sl_j + 1))
        done
        local _sl_q=${_sl_line:_sl_j:1}
        # The tag must be quoted. An unquoted tag makes the shell expand the
        # body, so a `$(...)` inside a commit message would execute.
        [[ "$_sl_q" == "'" || "$_sl_q" == '"' ]] || return 1
        _sl_j=$((_sl_j + 1))
        local _sl_tag=''
        while ((_sl_j < _sl_n)) && [[ "${_sl_line:_sl_j:1}" != "$_sl_q" ]]; do
          _sl_tag="$_sl_tag${_sl_line:_sl_j:1}"
          _sl_j=$((_sl_j + 1))
        done
        [[ "${_sl_line:_sl_j:1}" == "$_sl_q" ]] || return 1
        [[ -n "$_sl_tag" ]] || return 1
        scan_end_token
        SCAN_PENDING_TAGS[${#SCAN_PENDING_TAGS[@]}]=$_sl_tag
        _sl_i=$_sl_j
        ;;
      ';') scan_end_segment || return 1 ;;
      '&')
        [[ "${_sl_line:_sl_i+1:1}" == '&' ]] && _sl_i=$((_sl_i + 1))
        scan_end_segment || return 1
        ;;
      '|')
        [[ "${_sl_line:_sl_i+1:1}" == '|' ]] && _sl_i=$((_sl_i + 1))
        scan_end_segment || return 1
        ;;
      ' ' | $'\t') scan_end_token ;;
      # Unreachable: SCAN_UNQ_SPECIAL and this case list are the same set, and
      # every ordinary character was consumed by the run above. If they ever
      # drift, defer rather than treat an unhandled metacharacter as literal.
      *) return 1 ;;
    esac
    _sl_i=$((_sl_i + 1))
  done
  return 0
}

scan_command() {
  SCAN_PREDICATE=$2
  SCAN_QSTATE='' SCAN_CUR='' SCAN_HAVE_CUR=0 SCAN_DATA_NEWLINE=0 SCAN_SEGMENTS=0
  SCAN_TOKENS=()
  SCAN_PENDING_TAGS=()

  local _sc_lines=() _sc_line _sc_total _sc_li _sc_tag _sc_body _sc_found
  while IFS= read -r _sc_line; do
    _sc_lines[${#_sc_lines[@]}]=$_sc_line
  done <<<"$1"

  _sc_total=${#_sc_lines[@]}
  _sc_li=0
  while ((_sc_li < _sc_total)); do
    scan_line "${_sc_lines[_sc_li]}" || return 1
    _sc_li=$((_sc_li + 1))

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
      for _sc_tag in "${SCAN_PENDING_TAGS[@]}"; do
        _sc_found=0
        while ((_sc_li < _sc_total)); do
          _sc_body=${_sc_lines[_sc_li]}
          _sc_li=$((_sc_li + 1))
          # Accepting a leading-whitespace terminator is looser than bash (which
          # requires an exact match unless `<<-`). That errs towards ending the
          # body early, so a real command is never mistaken for message text.
          if [[ "${_sc_body#"${_sc_body%%[![:space:]]*}"}" == "$_sc_tag" ]]; then
            _sc_found=1
            break
          fi
        done
        ((_sc_found)) || return 1 # unterminated heredoc: unparseable
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
