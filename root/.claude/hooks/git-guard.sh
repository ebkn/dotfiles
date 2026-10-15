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
VALUED_WRAPPER_FLAG='^(nice (-n|--adjustment)|timeout (-s|-k|--signal|--kill-after)|stdbuf (-i|-o|-e)|xargs (-n|-I|-L|-P|-d|-s|-E|-a))$'
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
      nohup | builtin | noglob) continue ;;
      # Shell syntax that precedes a command without being one. Unlike the
      # wrappers above, Claude Code does not strip these, but the git after them
      # runs all the same.
      if | then | else | elif | while | until | do | '!' | '{') continue ;;
      timeout | nice | stdbuf | time | command | xargs)
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
split_segments() {
  printf '%s' "$1" | LC_ALL=C awk '
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
        n = split(L[ln], ch, ""); np = 0; joined = 0
        for (i = 1; i <= n; i++) {
          c = ch[i]
          if (c == "\\" && i == n && q != "\047") { joined = 1; break }
          if (q != "") {
            if (c == q) q = ""
            else if (q == "\"" && (c == "`" || (c == "$" && ch[i + 1] == "("))) exit 1
            else if (q == "\"" && c == "\\") { i++; c = c ch[i] }
          } else if (c == "\047" || c == "\"") q = c
          else if (c == "\\") { i++; c = c ch[i] }
          else if (c == "<" && ch[i + 1] == "<" && ch[i + 2] == "<") { c = "<<<"; i += 2 }
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
  segments=$(printf '%s' "$COMMAND" | sed -E 's/(\|\||&&|\|&|[;|&()`])/\n/g')
fi

# The loop below costs ~0.2ms a segment and more as they multiply (100000 took
# 56s), and a hook past its timeout lets the call through. So only segments
# where some token could read as the git command word reach it -- `git`,
# `/usr/bin/git`, `"git"`, each bounded by whitespace, a quote or an end -- and
# past MAX_CANDIDATES the command is refused unread: a real one never has that
# many git invocations, and refusing is the safe direction here.
MAX_CANDIDATES=1000
candidates=$(printf '%s\n' "$segments" | grep -E "(^|[[:space:]/\"'])git([\"'[:space:]]|\$)") && rc=0 || rc=$?
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
  strip_wrappers || continue

  [[ "$CMD_WORD" == "git" || "$CMD_WORD" == */git ]] || continue

  if ! scan_globals; then
    deny "git-guard: refused '${BAD}' before the git subcommand. Options in that position can make git execute an arbitrary program (e.g. -c core.fsmonitor=..., -c core.hooksPath=..., --git-dir into a repo with hooks), and the Bash allow rules cannot express argument position. Put the option after the subcommand, or run it yourself."
  fi
done <<<"$candidates"

exit 0
