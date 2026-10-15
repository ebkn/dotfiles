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
# What "a git invocation" means here is bounded by what an allow rule could
# approve, since the threat is a `git ...` rule waving the call through. So the
# wrappers stripped are the ones Claude Code itself strips before matching, and
# forms no `git ...` rule matches are left to the prompt: `env git`, `sudo git`,
# `sh -c "git ..."`, `g''it`, `\git`, `$(echo git) ...`.
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
# "<wrapper> <flag>" pairs whose value is the next token. Held in a variable so
# the pattern is read as written, with no backslash-escaped spaces.
VALUED_WRAPPER_FLAG='^(nice (-n|--adjustment)|timeout (-s|-k|--signal|--kill-after)|stdbuf (-i|-o|-e))$'
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
      # Shell syntax that precedes a command without being one. Unlike the
      # wrappers above, Claude Code does not strip these, but the git after them
      # runs all the same.
      if | then | else | elif | while | until | do | '!' | '{') continue ;;
      timeout | nice | stdbuf)
        local w=$TOKEN
        # Skip the wrapper's own flags, including the separate value some take
        # (`nice -n 5`, `timeout -s KILL`, `timeout -k 1`). Missing one is a
        # bypass, not a false deny: the value is read as the duration and the
        # duration as the command word, so the git after it goes unseen.
        while true; do
          saved_rest=$REST
          next_token && rc=0 || rc=$?
          [[ $rc -eq 0 ]] || {
            REST=$saved_rest
            return 1
          }
          [[ "$TOKEN" == -* ]] || break
          if [[ "$w $TOKEN" =~ $VALUED_WRAPPER_FLAG ]]; then
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

# Split the command into the simple commands it runs, one per output line.
#
# A heredoc body is data, not commands, and is dropped. `git commit -F - <<'EOF'`
# is the normal way to write a multi-line message here, and such a message
# routinely quotes git command lines -- this hook's own commit message did, and
# was refused by an earlier version of it. The opener is recognised in the same
# walk that tracks quotes, because recognising it apart from that is a bypass:
# a line-wise regex took `<<<EOF` and a quoted "<<EOF" for openers and dropped
# every later line unread. A body with no terminator is kept, for the same
# reason. A body that really is executed (`bash <<'EOF'`) is not a way around
# any of this: the outer command is then `bash`, which no `git ...` rule matches.
#
# Split on every shell operator Claude Code recognises as a command separator,
# but only outside quotes. Splitting inside them is not harmless: a quoted
# argument that happens to contain `git -C` or `git -c` -- an rg alternation such
# as "warn|git -C|hook" -- became a fragment of its own and was refused. A quoted
# newline is likewise data and is flattened to a space, and a backslash-newline
# joins two lines into one command, as the shell does.
#
# A command substitution or subshell runs a command of its own, so `(`, `)` and
# a backtick split too -- `echo $(git -c ...)` and `(git -c ...)` otherwise
# start with a word that is not git. Inside double quotes a substitution still
# runs, and tracking its nested quoting is more parser than this hook should
# be, so `$(` or a backtick there makes the command unsplittable instead.
#
# Returns 1 on unbalanced quoting or such a substitution, where the caller falls
# back to splitting at every operator, heredoc bodies included: for a deny-only
# hook, refusing too much is the safe direction.
#
# The walk is awk, byte-wise under LC_ALL=C, and prints as it goes. Both halves
# are about the 5s timeout, past which a hook lets the call through: a bash loop
# over `${s:i:1}` re-counts from the start for every index (a 200k-byte command
# took 25s), and so does building the result by `out = out c` in awk (1.6s).
# Every byte compared here is ASCII, and no byte of a multi-byte UTF-8 sequence
# is, so walking bytes splits exactly where walking characters would. On exit 1
# the partial output is discarded by the caller.
split_segments() {
  printf '%s' "$1" | LC_ALL=C awk '
    { L[NR] = $0 }
    END {
      q = ""
      for (ln = 1; ln <= NR; ln++) {
        s = L[ln]; n = length(s); np = 0; joined = 0
        for (i = 1; i <= n; i++) {
          c = substr(s, i, 1)
          if (c == "\\" && i == n && q != "\047") { joined = 1; break }
          if (q != "") {
            if (c == q) q = ""
            else if (q == "\"" && (c == "`" || (c == "$" && substr(s, i + 1, 1) == "("))) exit 1
            else if (q == "\"" && c == "\\") { i++; c = c substr(s, i, 1) }
          } else if (c == "\047" || c == "\"") q = c
          else if (c == "\\") { i++; c = c substr(s, i, 1) }
          else if (substr(s, i, 3) == "<<<") { c = "<<<"; i += 2 }
          else if (substr(s, i, 2) == "<<") {
            # <<TAG, <<-TAG, <<'\''TAG'\'', <<"TAG"; the quote, if any, is walked
            # as an ordinary quote afterwards.
            if (match(substr(s, i + 2), /^-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*/)) {
              t = substr(s, i + 2, RLENGTH); sub(/^-?[ \t]*[\047"]?/, "", t)
              tags[++np] = t
            }
            c = "<<"; i++
          }
          else if (index(";&|()`", c)) c = "\n"
          printf "%s", c
        }
        if (joined) continue
        if (q != "") { printf " "; continue }
        # Bodies follow the line in opener order, each through its terminator.
        # Leading whitespace is ignored on the terminator, which can only end a
        # body early -- more inspected, never less.
        for (k = 1; k <= np; k++) {
          for (t = ln + 1; t <= NR; t++) {
            b = L[t]; sub(/^[ \t]+/, "", b)
            if (b == tags[k]) break
          }
          if (t <= NR) ln = t
        }
        printf "\n"
      }
      exit (q != "")
    }'
}

if ! segments=$(split_segments "$COMMAND"); then
  segments=$(printf '%s' "$COMMAND" | sed -E 's/(\|\||&&|\|&|[;|&()`])/\n/g')
fi

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
