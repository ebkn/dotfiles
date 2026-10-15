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
# That is also why its parser is correct in one direction only, and must not be
# reused by a hook that allows. Every ambiguity is resolved toward "inspect it"
# or "refuse it": after a wrapper the first git word is taken as the command,
# an unsplittable command is split at every operator, a quoted newline becomes a
# space, and an input too large or unreadable is refused. A hook that approved
# whatever this parser calls a clean `git -C . status` would approve
# `timeout 5 rm -rf ~ git -C . status`.
#
# What "a git invocation" means here is bounded by what an allow rule could
# approve, since the threat is a `git ...` rule waving the call through. So the
# wrappers stripped are the ones Claude Code itself strips before matching, and
# forms no `git ...` rule matches are left to the prompt: `env git`, `sudo git`,
# `sh -c "git ..."`, `g''it`, `$(echo git) ...`. Which spellings of the git word
# are inspected is decided in one place, beside the prefilter below.
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

# Pull one shell word off the front of $REST into $TOKEN, with its quotes
# removed. A word is unquoted runs and quoted runs up to unquoted whitespace, so
# `-C "/path/with space"` and `FOO="a b"` are each one word -- reading only a
# leading quote split the latter in two and took `b"` for the command word,
# hiding the git after it. Applied to the words before a segment's command
# word, to the arguments after a wrapper up to the first git word, and to git's
# global options -- never past the git subcommand, so never a git commit
# message. Outside quotes a backslash escapes the next byte, so `a\ b` is one
# word as the shell reads it -- read as two, `git -C a\ b -c x status` took `b`
# for the subcommand. Quoting it does not model is refused rather than guessed
# at: a backslash inside double quotes, and ANSI-C `$'...'`. Guessing was a
# bypass -- `\"` closed the run early, a later `'` re-synchronised the quotes,
# and `-c` was read as part of a quoted subcommand that the shell ran as an
# option. A word this reads differently from the shell must only ever make the
# hook refuse more.
#
# A redirection is removed from argv, as the shell removes it: read as a word,
# `git -C . 2>/dev/null -c x status` took `2>/dev/null` for the subcommand and
# left `-c` unread, and `>/dev/null git ...` hid the command word. Only an
# unquoted digit run before the operator is a file descriptor; `"2">x` passes
# "2". The target is the rest of the word, or the next word when the operator
# ends one. More than one redirection in a word, or MAX_REDIRECTS in a row, is
# refused rather than modelled.
#
# An unquoted brace, glob or `$` is an expansion: the shell turns the word into
# other argv, so it is not what git receives. TOKEN_EXPANDS reports it, and
# TOKEN_VARIES a `$` inside double quotes -- one word, of unknown content. The
# caller decides: scan_globals refuses either where git reads an option, since
# `git -C . {-c,x} status` expands to one, and only an expansion as -C's path;
# before the git word they only mean "not a git word". `{}` alone is no brace
# expansion, so xargs' placeholder is read as written.
#
# Returns 1 when $REST holds no further word, 2 when the word cannot be read: an
# unterminated quote, quoting this does not model (a backslash inside double
# quotes, `$'`), a redirection beyond the above, or more than MAX_WORD_RUNS runs,
# since each run copies the rest of the string and a word built to have
# thousands would outlast the timeout.
REST=""
TOKEN=""
TOKEN_EXPANDS=0
TOKEN_VARIES=0
MAX_WORD_RUNS=64
MAX_REDIRECTS=16
EXPANDING='*[{*?[$]*'
next_token() {
  local rc redirects=0 word expands varies
  while true; do
    read_word && rc=0 || rc=$?
    [[ $rc -eq 0 ]] || return $rc
    if ((WORD_NEEDS_TARGET)); then
      word=$TOKEN expands=$TOKEN_EXPANDS varies=$TOKEN_VARIES
      read_word && rc=0 || rc=$?
      # An operator with no target is unreadable, not the end of the command:
      # the fallback split leaves `git >` of `git >&2 -c x status` that way.
      [[ $rc -eq 0 && $WORD_REDIRECTS -eq 0 ]] || return 2
      TOKEN=$word TOKEN_EXPANDS=$expands TOKEN_VARIES=$varies WORD_REDIRECTS=1
    fi
    if ((WORD_REDIRECTS)) && [[ -z "$TOKEN" ]]; then
      redirects=$((redirects + 1))
      ((redirects < MAX_REDIRECTS)) || return 2
      continue
    fi
    return 0
  done
}

# One word for next_token, which handles a redirection's separate target and
# words that are only a redirection. Sets TOKEN, TOKEN_EXPANDS, WORD_REDIRECTS
# (0 or 1) and WORD_NEEDS_TARGET.
WORD_REDIRECTS=0
WORD_NEEDS_TARGET=0
read_word() {
  REST="${REST#"${REST%%[![:space:]]*}"}"
  [[ -n "$REST" ]] || return 1
  local q body chunk op runs=0 quoted=0 in_target=0
  TOKEN="" TOKEN_EXPANDS=0 TOKEN_VARIES=0 WORD_REDIRECTS=0 WORD_NEEDS_TARGET=0
  while [[ -n "$REST" && "$REST" != [[:space:]]* ]]; do
    runs=$((runs + 1))
    ((runs <= MAX_WORD_RUNS)) || return 2
    case "$REST" in
      \'* | \"*)
        q="${REST:0:1}"
        body="${REST:1}"
        [[ "$body" == *"$q"* ]] || return 2
        chunk="${body%%"$q"*}"
        [[ "$q" == "'" || "$chunk" != *\\* ]] || return 2
        if [[ "$q" == '"' && "$chunk" == *\$* ]]; then TOKEN_VARIES=1; fi
        ((in_target)) || TOKEN+="$chunk"
        quoted=1
        REST="${body#*"$q"}"
        ;;
      \\*)
        ((in_target)) || TOKEN+="${REST:1:1}"
        quoted=1
        REST="${REST:2}"
        ;;
      [\<\>]*)
        ((in_target == 0)) || return 2
        op="${REST%%[!<>&|]*}"
        REST="${REST#"$op"}"
        in_target=1 WORD_REDIRECTS=1
        # An unquoted fd number, or the `&` of `&>`, belongs to the operator.
        if ((quoted == 0)) && [[ "$TOKEN" != *[!0-9]* || "$TOKEN" == "&" ]]; then TOKEN=""; fi
        [[ -n "$REST" && "$REST" != [[:space:]]* ]] || WORD_NEEDS_TARGET=1
        ;;
      *)
        chunk="${REST%%[[:space:]\'\"\\<>]*}"
        # `$'` opens ANSI-C quoting, whose own escapes this does not model.
        [[ "$chunk" != *\$ || "${REST:${#chunk}:1}" != "'" ]] || return 2
        if ((in_target == 0)); then
          # shellcheck disable=SC2053 # $EXPANDING is a pattern, deliberately unquoted
          if [[ "$chunk" == $EXPANDING && "$chunk" != "{}" ]]; then TOKEN_EXPANDS=1; fi
          TOKEN+="$chunk"
        fi
        REST="${REST#"$chunk"}"
        ;;
    esac
  done
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
        BAD="an unreadable word before the subcommand"
        return 1
        ;;
    esac
    # Here a quoted parameter is refused too: one word, but an option of its
    # content's choosing (`git "$X" status` with X=--exec-path=...).
    if ((TOKEN_EXPANDS || TOKEN_VARIES)); then
      BAD="an unreadable word before the subcommand"
      return 1
    fi

    # First non-option token is the subcommand: everything before it was clean.
    [[ "$TOKEN" == -* ]] || return 0

    if [[ "$TOKEN" == "-C" ]]; then
      next_token && rc=0 || rc=$?
      case $rc in
        1)
          BAD="-C with no path"
          return 1
          ;;
        2)
          BAD="an unreadable word after -C"
          return 1
          ;;
      esac
      if ((TOKEN_EXPANDS)); then
        BAD="an unreadable word after -C"
        return 1
      fi
      continue
    fi

    is_safe_global "$TOKEN" && continue

    BAD="$TOKEN"
    return 1
  done
}

# Find the word of a segment that git-guard treats as its command, skipping
# assignments and keywords, and seeing through the wrappers Claude Code itself
# strips before matching Bash rules, so `timeout 5 git -c ... status` is
# inspected rather than skipped. See: permissions.md (Wrappers).
#
# On success $CMD_WORD holds that word and $REST the words after it. Without a
# wrapper the word is the segment's command word; after one it is the first git
# word, even where the shell would read it as an argument -- deliberately, see
# below. Returns 1 when there is no such word (no command word, or no git word
# after a wrapper), 2 when a word before it cannot be read -- which the caller
# refuses, because skipping it would pass whatever git follows unread.
CMD_WORD=""
strip_wrappers() {
  local rc
  while true; do
    next_token && rc=0 || rc=$?
    [[ $rc -eq 0 ]] || return $rc

    case "$TOKEN" in
      # Leading environment assignment.
      [A-Za-z_]*=*) continue ;;
      # Shell syntax that precedes a command without being one. Unlike the
      # wrappers below, Claude Code does not strip these, but the git after them
      # runs all the same.
      if | then | else | elif | while | until | do | '!' | '{') continue ;;
      # After a wrapper, the first `git` word is taken as the command, with no
      # attempt to parse the wrapper's flags. Parsing them was a bypass each
      # time a form was missed -- `timeout -s KILL 5`, `stdbuf --output 0`,
      # `time -f %e` -- because the flag's value was read as the command word
      # and the git after it went unseen. The cost is refusing the rare wrapped
      # non-git command with a git word among its arguments, bare or as a path
      # (`timeout 5 echo git -c x`, `timeout 5 ls build/git -c x`).
      timeout | nice | stdbuf | time | command | xargs | nohup | builtin | noglob)
        while true; do
          next_token && rc=0 || rc=$?
          [[ $rc -eq 0 ]] || return $rc
          if is_git_word "$TOKEN"; then
            CMD_WORD=$TOKEN
            return 0
          fi
        done
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
# The walk is awk, byte-wise under LC_ALL=C, over each line split once into an
# array of bytes, printing as it goes. All of that is about the 5s timeout, past
# which a hook lets the call through: anything that re-counts from the start of
# the string per byte is quadratic, and three did -- a bash loop over `${s:i:1}`
# (200k bytes: 25s), `out = out c` in awk (1.6s), and even awk's own
# `substr(s, i, 1)` on macOS (700k bytes: 7.8s, against 0.4s for the array). A
# heredoc tag is likewise read byte by byte and capped in length, so no opener
# costs more than a constant. Every byte compared is ASCII, and no byte of a
# multi-byte UTF-8 sequence is, so walking bytes splits exactly where walking
# characters would. On exit 1 the partial output is discarded by the caller.
#
# SEPARATORS is shared with the fallback below: an operator only one of them
# splits at would hide the git after it on that path. The multi-byte operators
# (`&&`, `||`, `|&`) need no entry of their own, since splitting at each byte
# only adds empty segments, which are skipped.
SEPARATORS=';&|()`'
split_segments() {
  printf '%s' "$1" | LC_ALL=C awk -v seps="$SEPARATORS" '
    {
      L[NR] = $0
      # Index every line that could terminate a heredoc, so finding one is a
      # pointer step rather than a scan: scanning per opener is quadratic, and
      # 20000 unterminated openers took 60s -- past the timeout that lets the
      # call through.
      b = $0; sub(/^[ \t]+/, "", b)
      if (b ~ /^[A-Za-z_][A-Za-z0-9_]*$/) pos[b, ++cnt[b]] = NR
    }
    END {
      q = ""
      for (ln = 1; ln <= NR; ln++) {
        n = split(L[ln], ch, ""); np = 0; joined = 0; lu = ""
        for (i = 1; i <= n; i++) {
          c = ch[i]
          if (c == "\\" && i == n && q != "\047") { joined = 1; break }
          if (q != "") {
            if (c == q) q = ""
            else if (q == "\"" && (c == "`" || (c == "$" && ch[i + 1] == "("))) exit 1
            else if (q == "\"" && c == "\\") { i++; c = c ch[i] }
          } else if (c == "\047" || c == "\"") { q = c; lu = "" }
          else if (c == "\\") { i++; c = c ch[i]; lu = "" }
          else if (c == "<" && ch[i + 1] == "<" && ch[i + 2] == "<") { c = "<<<"; i += 2; lu = "" }
          else if (c == "<" && ch[i + 1] == "<") {
            # <<TAG, <<-TAG, << TAG, <<'\''TAG'\'', <<"TAG"; the quote, if any,
            # is walked as an ordinary quote afterwards. A tag past 64 bytes is
            # not taken as one, which keeps its body inspected.
            j = i + 2
            if (ch[j] == "-") j++
            while (ch[j] == " " || ch[j] == "\t") j++
            if (ch[j] == "\047" || ch[j] == "\"") j++
            t = ""
            if (ch[j] ~ /[A-Za-z_]/)
              while (ch[j] ~ /[A-Za-z0-9_]/ && length(t) <= 64) t = t ch[j++]
            if (t != "" && length(t) <= 64) tags[++np] = t
            c = "<<"; i++; lu = ""
          }
          # The & of >&, <&, &> and the | of >| belong to a redirection, which
          # the word reader removes; split there, `git >&2 -c x status` became
          # a bare `git` and a command `2 -c x status`. lu is the previous
          # unquoted byte, so a quoted ">" before & leaves it a separator.
          else if (c == "&" && (lu == "<" || lu == ">" || ch[i + 1] == ">")) lu = c
          else if (c == "|" && lu == ">") lu = c
          else if (index(seps, c)) { c = "\n"; lu = "" }
          else lu = c
          printf "%s", c
        }
        if (joined) continue
        if (q != "") { printf " "; continue }
        # Bodies follow the line in opener order, each through its terminator.
        # Leading whitespace is ignored on the terminator, which can only end a
        # body early -- more inspected, never less.
        # ln only grows, so each tag pointer only moves forward.
        for (k = 1; k <= np; k++) {
          tg = tags[k]
          while (ptr[tg] < cnt[tg] && pos[tg, ptr[tg] + 1] <= ln) ptr[tg]++
          if (ptr[tg] < cnt[tg]) ln = pos[tg, ptr[tg] + 1]
        }
        printf "\n"
      }
      exit (q != "")
    }'
}

if ! segments=$(split_segments "$COMMAND"); then
  segments=$(printf '%s' "$COMMAND" | sed "s/[${SEPARATORS}]/\n/g")
fi

# The loop below costs ~0.2ms a segment and more as they multiply (100000 took
# 56s), and a hook past its timeout lets the call through. So only segments
# where some token could read as the git command word reach it, and this regex
# is where the inspected spellings are decided: `git`, `/usr/bin/git`, `"git"`,
# `'git'`, `\git`, bounded by whitespace, a quote or an end. A spelling missing
# here is never inspected, however next_token would read it -- which is
# deliberate for those no `git ...` rule matches (`g''it`, `"g"it`, `g\it`), and
# a bypass for any that a rule does.
#
# The regex sees the raw text; is_git_word sees a word with its quotes removed,
# and is the one test both the segment head and the wrapper loop apply. A
# spelling the regex lets through and is_git_word rejects is never inspected,
# so the two change together.
#
# Past MAX_CANDIDATES the command is refused unread: a real one never has that
# many git invocations, and refusing is the safe direction here.
is_git_word() { [[ "$1" == git || "$1" == */git ]]; }
MAX_CANDIDATES=1000
candidates=$(printf '%s\n' "$segments" | grep -E "(^|[[:space:]/\"'\\\\])git([\"'[:space:]]|\$)") && rc=0 || rc=$?
case $rc in
  0) ;;
  1) exit 0 ;; # no segment mentions git
  *) deny "git-guard: could not filter the command for git invocations (grep exited $rc), so it was refused rather than passed unread." ;;
esac
n_candidates=$(grep -c '' <<<"$candidates")
if ((n_candidates > MAX_CANDIDATES)); then
  deny "git-guard: ${n_candidates} segments look like git invocations, more than the ${MAX_CANDIDATES} it inspects within its timeout. Split the command."
fi

while IFS= read -r segment; do
  segment="${segment#"${segment%%[![:space:]]*}"}"
  [[ -n "$segment" ]] || continue

  REST=$segment
  strip_wrappers && rc=0 || rc=$?
  case $rc in
    1) continue ;;
    2) deny "git-guard: could not read the words before the command in a segment that may run git, so it was refused rather than passed unread." ;;
  esac

  is_git_word "$CMD_WORD" || continue

  if ! scan_globals; then
    deny "git-guard: refused '${BAD}' before the git subcommand. Options in that position can make git execute an arbitrary program (e.g. -c core.fsmonitor=..., -c core.hooksPath=..., --git-dir into a repo with hooks), and the Bash allow rules cannot express argument position. Put the option after the subcommand, or run it yourself."
  fi
done <<<"$candidates"

exit 0
