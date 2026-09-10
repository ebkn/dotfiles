#!/bin/bash
# Deny git invocations that carry a dangerous *global* option -- one that
# appears before the subcommand and makes git run a program of the caller's
# choosing.
#
# Why a hook instead of tightening the allow rules: Bash permission patterns
# are literal text plus `*`, and `*` matches any text *including spaces*. The
# grammar has no way to express "this wildcard is one argument", so a rule like
# `Bash(git -C * add *)` necessarily also matches
# `git -C "dir -c core.fsmonitor=<cmd>" add .`. Anthropic documents this and
# names the vector: "In `Bash(git * main)` [the `*`] stands in for the
# subcommand, so Claude Code matches every git subcommand and every option
# before it. That includes `-c`, which makes git run a program you name."
# The same page recommends a PreToolUse hook for argument constraints.
# See: https://code.claude.com/docs/en/permissions.md (Wildcard patterns)
#
# Verified vectors (git 2.55.0), all reachable through the `git -C *` rules:
#   git -c core.fsmonitor='<cmd>' status   -- runs on status/add/diff, no tty needed
#   git -c core.hooksPath=<dir> commit     -- runs <dir>/pre-commit
#   git -c diff.external='<cmd>' diff      -- runs the external differ
# `--exec-path` is NOT a vector for the allow-listed subcommands: they are all
# builtins, which git dispatches before consulting exec-path.
#
# The check is a *positive* safelist of the tokens allowed before the
# subcommand. git's global options are a small closed set (see `git --help`),
# so anything unrecognised -- including options git adds in future -- is denied
# rather than waved through. This is the opposite of a blocklist and is why the
# rule set does not need revisiting every git release.
#
# Scope: this hook only ever emits "deny". It never emits "allow", so it cannot
# widen anything; the existing allow/deny/ask rules keep deciding every command
# it stays silent on.
#
# Registered without an `if:` filter, unlike curl-guard. A filter is itself a
# Bash permission pattern and so inherits the same blind spot this hook exists
# to cover -- `echo hi; git -c ... status` and wrapper forms could be filtered
# out before the hook ever saw them. The substring bail-out below is cheap
# enough that running on every Bash call costs nothing.
#
# Docs: https://docs.claude.com/en/hooks

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

[[ -n "$COMMAND" ]] || exit 0

# Cheap bail-out. Deliberately a plain substring test rather than a word-
# boundary regex: an absolute path such as /usr/bin/git must still reach the
# parser, which decides what is really a git invocation from the command word.
[[ "$COMMAND" == *git* ]] || exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# git's global options that cannot make git execute a program of our choosing.
# -C is handled separately because it consumes the following token.
is_safe_global() {
  case "$1" in
    -p | --paginate | -P | --no-pager | \
      --no-replace-objects | --no-lazy-fetch | --no-optional-locks | --no-advice | \
      --literal-pathspecs | --glob-pathspecs | --noglob-pathspecs | --icase-pathspecs | \
      -v | --version | -h | --help | --html-path | --man-path | --info-path)
      return 0
      ;;
  esac
  return 1
}

# Pull one whitespace-separated token off the front of $REST, honouring simple
# quoting so that `-C "/path/with space"` is read as a single token. Only ever
# applied to the region before the subcommand, which is options and paths --
# never a commit message -- so this does not need to be a full shell parser.
REST=""
TOKEN=""
next_token() {
  REST="${REST#"${REST%%[![:space:]]*}"}"
  [[ -n "$REST" ]] || return 1
  local q body
  case "$REST" in
    \'* | \"*)
      q="${REST:0:1}"
      body="${REST:1}"
      # An unterminated quote in the option region is unparseable, not benign.
      [[ "$body" == *"$q"* ]] || return 2
      TOKEN="${body%%"$q"*}"
      REST="${body#*"$q"}"
      ;;
    *)
      TOKEN="${REST%%[[:space:]]*}"
      if [[ "$TOKEN" == "$REST" ]]; then REST=""; else REST="${REST#"$TOKEN"}"; fi
      ;;
  esac
  return 0
}

# Walk the tokens after `git` up to the subcommand. Returns 0 when the region
# is clean, 1 with $BAD set when it is not.
BAD=""
scan_globals() {
  local rc
  while true; do
    next_token && rc=0 || rc=$?
    case $rc in
      1) return 0 ;; # bare `git`
      2)
        BAD="unparseable quoting before the subcommand"
        return 1
        ;;
    esac

    # First non-option token is the subcommand: everything before it was clean.
    [[ "$TOKEN" == -* ]] || return 0

    if [[ "$TOKEN" == "-C" ]]; then
      next_token && rc=0 || rc=$?
      [[ $rc -eq 0 ]] || {
        BAD="-C with no path"
        return 1
      }
      continue
    fi

    is_safe_global "$TOKEN" && continue

    BAD="$TOKEN"
    return 1
  done
}

# Strip the wrappers Claude Code itself strips before matching Bash rules, so
# `timeout 5 git -c ... status` is inspected rather than skipped. On success
# $CMD_WORD holds the segment's command word and $REST its arguments.
# See: permissions.md (Wrappers).
CMD_WORD=""
strip_wrappers() {
  local rc
  while true; do
    local saved_rest=$REST
    next_token && rc=0 || rc=$?
    [[ $rc -eq 0 ]] || {
      REST=$saved_rest
      return 1
    }

    case "$TOKEN" in
      # Leading environment assignment.
      [A-Za-z_]*=*) continue ;;
      time | nohup | command | builtin | noglob | xargs) continue ;;
      timeout | nice | stdbuf)
        local w=$TOKEN
        # Skip the wrapper's own flags, including the value `nice -n` takes.
        while true; do
          saved_rest=$REST
          next_token && rc=0 || rc=$?
          [[ $rc -eq 0 ]] || {
            REST=$saved_rest
            return 1
          }
          [[ "$TOKEN" == -* ]] || break
          if [[ "$w" == "nice" && "$TOKEN" == "-n" ]]; then
            next_token && rc=0 || rc=$?
            [[ $rc -eq 0 ]] || return 1
          fi
        done
        # $TOKEN is now the first non-flag word: a duration for `timeout`,
        # otherwise already the command, so put it back for the caller.
        [[ "$w" == "timeout" ]] || REST="$TOKEN $REST"
        continue
        ;;
      *)
        CMD_WORD=$TOKEN
        return 0
        ;;
    esac
  done
}

# A heredoc body is data, not commands. `git commit -F - <<'EOF'` is the normal
# way to write a multi-line message here, and such a message routinely quotes
# git command lines -- this hook's own commit message did, and was refused by an
# earlier version of it. Drop those bodies before segmenting.
#
# A body that really is executed (`bash <<'EOF'`) is not a way around this: the
# outer command is then `bash`, which has no allow rule of its own, so the
# permission prompt decides it rather than any `git ...` rule.
strip_heredoc_bodies() {
  local line tag="" trimmed out=""
  while IFS= read -r line; do
    if [[ -n "$tag" ]]; then
      trimmed="${line#"${line%%[![:space:]]*}"}"
      [[ "$trimmed" == "$tag" ]] && tag=""
      continue
    fi
    out+="$line"$'\n'
    # `<<TAG`, `<<'TAG'`, `<<"TAG"`, `<<-TAG`. The `[A-Za-z_]` requirement means
    # a here-string (`<<<`) is not mistaken for a heredoc opener.
    if [[ "$line" =~ \<\<-?[[:space:]]*[\'\"]?([A-Za-z_][A-Za-z0-9_]*) ]]; then
      tag="${BASH_REMATCH[1]}"
    fi
  done <<<"$1"
  printf '%s' "$out"
}
COMMAND=$(strip_heredoc_bodies "$COMMAND")

# Split on every shell operator Claude Code recognises as a command separator.
# A `&&` or `;` inside a quoted commit message splits into a fragment that does
# not start with `git`, which is simply skipped -- no false deny.
segments=$(printf '%s' "$COMMAND" | sed -E 's/(\|\||&&|\|&|[;|&])/\n/g')

while IFS= read -r segment; do
  segment="${segment#"${segment%%[![:space:]]*}"}"
  [[ -n "$segment" ]] || continue

  REST=$segment
  strip_wrappers || continue

  [[ "$CMD_WORD" == "git" || "$CMD_WORD" == */git ]] || continue

  if ! scan_globals; then
    deny "git-guard: refused '${BAD}' before the git subcommand. Options in that position can make git execute an arbitrary program (e.g. -c core.fsmonitor=..., -c core.hooksPath=..., --git-dir into a repo with hooks), and the Bash allow rules cannot express argument position. Put the option after the subcommand, or run it yourself."
  fi
done <<<"$segments"

exit 0
