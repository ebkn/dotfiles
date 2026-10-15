#!/bin/bash
# Exercises git-guard.sh. DENY = hook blocks the call. PASS = hook stays
# silent, leaving the existing permission rules to decide as they do today.
#
# The PASS half is the half that matters for day-to-day use: this repo's
# monorepo layout means the agent routinely runs `git -C <absolute path> add`,
# and a hook that got in the way of that would not survive contact.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-guard.sh"

pass=0
fail=0

# PASS means exactly "exit 0, nothing on stdout" -- the hook staying out of the
# way. Anything else that is not a deny is ERROR, so a hook that crashes on an
# input cannot be mistaken for one that let it through on purpose.
run_hook() {
  jq -Rn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' | "$HOOK" 2>/dev/null
}
verdict() {
  local cmd=$1 out rc
  out=$(run_hook "$cmd") && rc=0 || rc=$?
  if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then
    echo DENY
  elif [[ $rc -eq 0 && -z "$out" ]]; then
    echo PASS
  else
    echo "ERROR(rc=$rc)"
  fi
}

check() {
  local expect=$1 cmd=$2 got
  got=$(verdict "$cmd")
  if [[ "$got" == "$expect" ]]; then
    pass=$((pass + 1))
    printf '  ok   %-4s %s\n' "$got" "$cmd"
  else
    fail=$((fail + 1))
    printf '  FAIL want=%s got=%s  %s\n' "$expect" "$got" "$cmd"
  fi
}

echo "-- must DENY: verified execution vectors --"
check DENY "git -c core.fsmonitor='echo pwned' status"
check DENY "git -C /tmp -c core.hooksPath=/tmp/e commit -m x"
check DENY "git -c diff.external='echo pwned' diff"
check DENY 'git --config-env=core.pager=EV status'

echo "-- must DENY: other options that reach a program --"
check DENY 'git --exec-path=/tmp/e add .'
check DENY 'git --git-dir=/tmp/e/.git commit -m x'
check DENY 'git --work-tree=/tmp/e add .'
check DENY 'git --namespace=x push'
check DENY 'git -C /tmp --bare status'

echo "-- must DENY: unknown option before the subcommand (safelist, not blocklist) --"
check DENY 'git --some-future-option add .'
check DENY 'git -Z add .'

echo "-- must DENY: reached through the wrappers Claude Code strips --"
check DENY 'timeout 5 git -c a=b status'
check DENY 'timeout --preserve-status 5 git -c a=b status'
check DENY 'nice -n 5 git -c a=b status'
check DENY 'stdbuf -o0 git -c a=b status'
check DENY 'nohup git -c a=b status'
check DENY 'xargs git -c a=b status'
check DENY 'FOO=bar git -c a=b status'
check DENY '/usr/bin/git -c a=b status'

echo "-- must DENY: hiding behind a separator or unparseable quoting --"
check DENY 'echo hi; git -c a=b status'
check DENY 'ls && git -c a=b status'
check DENY "git -C '/unterminated status"
check DENY 'git -C'
check DENY 'timeout 5 git -C'

echo "-- must DENY: wrapper flags that take a value are not the command --"
# Claude Code strips `timeout` before matching, so `Bash(git status*)` would
# approve these; reading `KILL` as the duration made `5` the command word.
check DENY 'timeout -s KILL 5 git -c a=b status'
check DENY 'timeout -k 1 5 git -c a=b status'
check DENY 'timeout --signal KILL 5 git -c a=b status'
check DENY 'timeout --kill-after=1 5 git -c a=b status'
check DENY 'stdbuf -o 0 git -c a=b status'
check DENY 'stdbuf -i 0 git -c a=b status'
check DENY 'stdbuf -e 0 git -c a=b status'
check DENY 'timeout --signal=KILL 5 git -c a=b status'
check DENY 'nice -n5 git -c a=b status'
check DENY 'nice --adjustment 5 git -c a=b status'
check DENY 'nice --adjustment=5 git -c a=b status'

echo "-- must DENY: every wrapper Claude Code strips is seen through --"
check DENY 'time git -c a=b status'
check DENY 'command git -c a=b status'
check DENY 'builtin git -c a=b status'
check DENY 'noglob git -c a=b status'

# Paths here are placeholders on purpose: this repository is public, so a real
# private-repo path in a test fixture would publish it.
echo "-- must PASS: a monorepo's everyday git -C usage --"
check PASS 'git -C /tmp add .'
check PASS 'git -C /Users/x/ghq/github.com/acme/example-monorepo/git-worktrees/some-branch add apps/frontend'
check PASS 'git -C "/path with space" add .'
check PASS 'git -C /tmp commit -m "fix: something"'
check PASS 'git -C /tmp'
check PASS 'git -C /tmp status --short'

echo "-- must PASS: -c after the subcommand is a different option entirely --"
check PASS 'git switch -c feat/x'
check PASS 'git -C /tmp switch -c feat/x'
check PASS 'git commit -c HEAD --amend'
check PASS 'git branch -c old new'
check PASS 'git log -c'

echo "-- must PASS: safe globals and ordinary commands --"
check PASS 'git status'
check PASS 'git'
check PASS 'git --no-pager log --oneline'
check PASS 'git -P diff'
check PASS 'git --no-optional-locks status'
check PASS 'git --paginate log'
check PASS 'git --no-replace-objects log'
check PASS 'git --no-lazy-fetch log'
check PASS 'git --no-advice status'
check PASS 'git --literal-pathspecs add a'
check PASS 'git --glob-pathspecs add a'
check PASS 'git --noglob-pathspecs add a'
check PASS 'git --icase-pathspecs add a'
check PASS 'git -v'
check PASS 'git --version'
check PASS 'git -h'
check PASS 'git --man-path'
check PASS 'git --html-path'
check PASS 'timeout 5 git status'
check PASS 'nice -n 5 git status'
check PASS 'git add -p'

echo "-- must PASS: quoting the subcommand region does not reach --"
check PASS "git commit -m \"it's broken\""
check PASS 'git commit -m "fix: a && b"'
check PASS 'git commit -m "wip; more"'
check PASS 'git log --grep="a|b"'
check PASS 'git commit -m "fix(scope): subject"'

echo "-- must PASS: heredoc bodies are data, not commands --"
# Regression: this hook's own commit message quoted `git -c ...` as an example,
# and an earlier version of the hook refused the commit.
check PASS $'git commit -F - <<\'EOF\'\nfix(claude): guard git global options\n\nVerified that `git -c core.fsmonitor=<cmd> status` executes.\nEOF'
check PASS $'git -C /tmp commit -F - <<\'MSG\'\nsubject\n\ngit --exec-path=/tmp/e add .\nMSG'
check PASS $'cat <<-EOF\n\tgit -c a=b status\n\tEOF'

echo "-- must DENY: a real invocation outside the heredoc still counts --"
check DENY $'git -c a=b commit -F - <<\'EOF\'\nsubject\nEOF'
check DENY $'cat <<\'EOF\'\ngit -c harmless=example status\nEOF\ngit -c a=b status'

echo "-- must DENY: what only looks like a heredoc opener hides nothing --"
check DENY $'cat <<<EOF\ngit -c a=b status'
check DENY $'echo "<<EOF"\ngit -c a=b status\nEOF'
check DENY $'echo \'<<EOF\'\ngit -c a=b status\nEOF'
check DENY $'echo \\<<EOF\ngit -c a=b status\nEOF'
# No terminator: stripping to the end would hide every later line, so the body
# is inspected rather than assumed to be data.
check DENY $'cat <<EOF\ngit -c a=b status'
check DENY $'cat <<A <<B\na\nA\nb\nB\ngit -c a=b status'
check PASS $'cat <<A <<B\ngit -c a=b status\nA\ngit -c a=b status\nB'

echo "-- must DENY: a backslash-newline continues the same command --"
check DENY $'git \\\n-c a=b status'
check PASS $'git status \\\n--short'

echo "-- must PASS: not a git command --"
check PASS 'npm test'
check PASS 'echo git -c a=b'
check PASS 'grep git -c file.txt'
check PASS 'rg "git -c" .'

echo "-- must PASS: a separator inside quotes (outside any substitution) does not start a command --"
# Regression: an rg alternation `"warn|git -C|hook"` was split at the quoted
# `|`, leaving a bare `git -C` fragment that was refused as "-C with no path".
check PASS 'rg -n "warn|git -C|hook" file.txt'
check PASS 'rg "x; git -c a=b status" .'
check PASS "echo 'a && git -c a=b status'"
check PASS 'echo "a \" ; git -c a=b status"'
check PASS 'echo a\; git -c a=b status'
check PASS $'git commit -m "subject\ngit -c a=b status"'

echo "-- must DENY: a separator outside quotes still does --"
check DENY 'echo "hi"; git -c a=b status'
check DENY "echo 'x' && git -c a=b status"
check DENY $'echo "multi\nline"\ngit -c a=b status'
# Unbalanced quoting cannot be segmented reliably, so it falls back to splitting
# at every operator: refusing too much is the safe direction for a deny-only hook.
check DENY 'echo "x; git -c a=b status'
# A backslash is literal inside single quotes, so `'a\'` is closed there; treating
# it as an escape would swallow the closing quote and hide the git that follows.
check DENY "echo 'a\\' ; git -c a=b status"
# An escaped quote outside quotes opens nothing.
check DENY 'echo \"; git -c a=b status'

echo "-- must DENY: a command substitution runs, even inside double quotes --"
# The substitutions are the command text under test, so they must stay unexpanded.
# shellcheck disable=SC2016
{
  check DENY 'echo "$(true; git -c a=b status)"'
  check DENY 'echo "`true; git -c a=b status`"'
  check DENY 'echo "$(git -c a=b status)"'
  check DENY 'echo $(git -c a=b status)'
  check DENY 'echo `git -c a=b status`'
  check DENY 'x=$(git -c a=b status)'
}
check PASS "echo '\$(git -c a=b status)'"

echo "-- must DENY: grouping and compound-command keywords are not the command --"
check DENY '(git -c a=b status)'
check DENY '( git -c a=b status )'
check DENY '{ git -c a=b status; }'
check DENY 'if git -c a=b status; then echo y; fi'
check DENY 'while git -c a=b status; do break; done'
check DENY 'true && ! git -c a=b status'
check DENY 'until git -c a=b status; do break; done'
check DENY 'if false; then :; elif git -c a=b status; then :; fi'
check DENY 'if false; then git -c a=b status; fi'
check DENY 'if false; then :; else git -c a=b status; fi'

echo "-- must DENY: every separator Claude Code recognises --"
check DENY 'false || git -c a=b status'
check DENY 'echo | git -c a=b status'
check DENY 'echo |& git -c a=b status'
check DENY 'sleep 1 & git -c a=b status'
check DENY 'cat <(git -c a=b status)'
# shellcheck disable=SC2016 # literal command text under test
check DENY 'echo "$x" "$(git -c a=b status)"'

echo "-- must DENY: the option itself quoted or glued --"
check DENY 'git "-c" a=b status'
check DENY 'git -c"a=b" status'

echo "-- must PASS: input with nothing to inspect --"
check_input() {
  local label=$1 json=$2 out rc
  out=$(printf '%s' "$json" | "$HOOK" 2>/dev/null) && rc=0 || rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then
    pass=$((pass + 1))
    printf '  ok   PASS %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL want=PASS got=rc=%s out=%s  %s\n' "$rc" "$out" "$label"
  fi
}
check_input "no tool_input" '{}'
check_input "no command" '{"tool_name":"Bash","tool_input":{}}'
check_input "empty command" '{"tool_name":"Bash","tool_input":{"command":""}}'

echo "-- the reason names the refused option --"
reason=$(run_hook 'git -c a=b status' | jq -r '.hookSpecificOutput.permissionDecisionReason')
if [[ "$reason" == *"refused '-c'"* ]]; then
  pass=$((pass + 1))
  echo "  ok   reason names '-c'"
else
  fail=$((fail + 1))
  printf '  FAIL reason does not name -c: %s\n' "$reason"
fi

echo "-- must finish well inside the 5s hook timeout --"
# A timed-out hook does not block the call, so slowness is a bypass, not a
# nuisance. Measured on 100k bytes: the linear awk walk takes ~0.35s, a bash
# loop over `${s:i:1}` ~9s even under LC_ALL=C (it is quadratic), so a 3s bound
# tells them apart with room for a slow CI runner. Both paths are timed: the awk
# walk, and the sed fallback that unbalanced quoting falls through to.
# Each case ends in a git that must be refused, so a hook that bails out early
# on a huge input fails here rather than looking fast.
check_fast() {
  local label=$1 cmd=$2 got
  SECONDS=0
  got=$(verdict "$cmd")
  if ((SECONDS < 3)) && [[ "$got" == DENY ]]; then
    pass=$((pass + 1))
    printf '  ok   %s: DENY in %ds\n' "$label" "$SECONDS"
  else
    fail=$((fail + 1))
    printf '  FAIL %s: %s in %ds\n' "$label" "$got" "$SECONDS"
  fi
}
filler=$(printf 'é%.0s' $(seq 50000))
check_fast "100k-byte quoted message" "git commit -m \"$filler\"; git -c a=b status"
check_fast "100k-byte unbalanced quote (fallback)" "git commit -m \"$filler; git -c a=b status"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
