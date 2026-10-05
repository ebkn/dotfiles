#!/bin/bash
#
# ci-enrollment.test.sh
#
# Pins that every test suite in the repo is run by CI, or is named below with
# the reason it is not. The workflow lists its suites by hand, one step each, so
# a suite can be written, documented as gating CI and still run nowhere --
# which is how tmux-agent-view.test.sh, autossh-ssh.test.sh and
# zshenv-autofs.test.zsh spent their lives until this check existed.
#
# A suite counts as enrolled when a step in lint-and-test.yml is exactly
# `run: bash <path>` or `run: zsh <path>`, the only form the workflow uses.
#
# Static: reads git and the workflow file, runs nothing.

set -eo pipefail

cd "$(dirname "$0")/.."
workflow=.github/workflows/lint-and-test.yml
fails=0
fail() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

# Suites deliberately left out of CI. Each needs its reason, here and in the
# doc that owns it; an entry whose file is gone or that CI now runs fails below,
# so the list cannot quietly outlive its reasons.
#   git-guard.test.sh  -- not wired in yet (CLAUDE.md, Testing)
#   default.rules.test.sh -- needs the codex binary; local only (root/README.md)
not_in_ci='root/.claude/hooks/git-guard.test.sh
root/.codex/rules/default.rules.test.sh'

# Listings that fail must not read as "there is nothing to check".
if ! suites=$(git ls-files -- '*.test.sh' '*.test.zsh'); then
  fail "could not list the test suites"
fi
if ! enrolled=$(awk '$1 == "run:" && ($2 == "bash" || $2 == "zsh") && NF == 3 { print $3 }' "$workflow"); then
  fail "could not read $workflow"
fi

# A here-string, not `printf | grep -q`: under pipefail, grep -q exiting on its
# match can SIGPIPE the writer and turn a match into status 141 -- which the
# not_in_ci check below would read as "CI does not run it" and pass.
listed() { # <needle> <newline-separated list>
  grep -qxF -- "$1" <<<"$2"
}

count=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  count=$((count + 1))
  listed "$f" "$not_in_ci" && continue
  listed "$f" "$enrolled" ||
    fail "$f is not run by $workflow (add a step, or list it in not_in_ci with the reason)"
done <<<"$suites"

while IFS= read -r f; do
  [ -n "$f" ] || continue
  listed "$f" "$suites" || fail "not_in_ci names $f, which is not a tracked suite"
  listed "$f" "$enrolled" && fail "not_in_ci names $f, but CI runs it"
done <<<"$not_in_ci"

# A listing that found almost nothing would make the loops above vacuous. A
# floor, not the exact count, so adding a suite does not mean editing this.
[ "$count" -ge 20 ] || fail "found only $count suite(s); the listing is broken"

if [ "$fails" -eq 0 ]; then
  printf 'ok   all %d suites are run by CI or listed as not_in_ci\n' "$count"
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
