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

check() {
  local expect=$1 cmd=$2 out got
  out=$(jq -Rn --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}' | "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then
    got=DENY
  else
    got=PASS
  fi
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

echo "-- must PASS: the monorepo's everyday git -C usage --"
check PASS 'git -C /tmp add .'
check PASS 'git -C /Users/x/ghq/github.com/eversteel/tetsunavi-monorepo/git-worktrees/fix-claude-settings add apps/eaf-frontend'
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
check PASS 'timeout 5 git status'
check PASS 'nice -n 5 git status'
check PASS 'git add -p'

echo "-- must PASS: quoting the subcommand region does not reach --"
check PASS "git commit -m \"it's broken\""
check PASS 'git commit -m "fix: a && b"'
check PASS 'git commit -m "wip; more"'
check PASS 'git log --grep="a|b"'

echo "-- must PASS: heredoc bodies are data, not commands --"
# Regression: this hook's own commit message quoted `git -c ...` as an example,
# and an earlier version of the hook refused the commit.
check PASS $'git commit -F - <<\'EOF\'\nfix(claude): guard git global options\n\nVerified that `git -c core.fsmonitor=<cmd> status` executes.\nEOF'
check PASS $'git -C /tmp commit -F - <<\'MSG\'\nsubject\n\ngit --exec-path=/tmp/e add .\nMSG'
check PASS $'cat <<-EOF\n\tgit -c a=b status\n\tEOF'

echo "-- must DENY: a real invocation outside the heredoc still counts --"
check DENY $'git -c a=b commit -F - <<\'EOF\'\nsubject\nEOF'
check DENY $'cat <<\'EOF\'\ngit -c harmless=example status\nEOF\ngit -c a=b status'

echo "-- must PASS: not a git command --"
check PASS 'npm test'
check PASS 'echo git -c a=b'
check PASS 'grep git -c file.txt'
check PASS 'rg "git -c" .'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
