#!/bin/bash
#
# ci-enrollment.test.sh
#
# Pins that every *.test.sh and *.test.zsh suite in the repo is run by CI, or
# is left out by bin/test with its reason. A *.test.ps1 is NOT checked here: it
# is enrolled by hand in windows-setup.yml, and nothing fails if it is not.
#
# CI no longer lists its suites: the test job runs bin/test, which discovers
# them with git ls-files. The hand-written list this file used to police --
# under which tmux-agent-view.test.sh, autossh-ssh.test.sh and
# zshenv-autofs.test.zsh spent their lives running nowhere -- is gone. What can
# still go wrong is the step that runs the runner, and the runner's own list of
# exclusions (bin/test.skip). So:
#   - the workflow runs bin/test;
#   - in CI's environment, bin/test --list runs or skips every tracked suite,
#     and skips one only for a reason it prints;
#   - bin/test --list succeeds -- it refuses an exclusion naming no tracked
#     suite itself, since only it can see one (a skip line is printed only for
#     a suite the listing found, so a stale entry never shows up here).
#
# Static: reads git, the workflow file and bin/test --list; runs no suite.

set -eo pipefail

cd "$(dirname "$0")/.."
workflow=.github/workflows/lint-and-test.yml
fails=0
fail() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

# Listings that fail must not read as "there is nothing to check".
if ! suites=$(git ls-files -- '*.test.sh' '*.test.zsh'); then
  fail "could not list the test suites"
fi
if ! steps=$(awk '$1 == "run:" { $1 = ""; sub(/^ /, ""); print }' "$workflow"); then
  fail "could not read $workflow"
fi
# CI is GITHUB_ACTIONS=true, where the tmux suites run too.
if ! listed=$(GITHUB_ACTIONS=true bin/test --list); then
  fail "bin/test --list failed"
fi

# A here-string, not `printf | grep -q`: under pipefail, grep -q exiting on its
# match can SIGPIPE the writer and turn a match into status 141.
listed_as() { # <run|skip> <suite>
  grep -qE "^$1 +$(printf '%s' "$2" | sed 's/[.[\*^$/]/\\&/g')( |\$)" <<<"$listed"
}

grep -qxF 'bin/test' <<<"$steps" ||
  fail "$workflow has no \`run: bin/test\` step, so CI runs no suite"

count=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  count=$((count + 1))
  if listed_as run "$f"; then
    continue
  elif listed_as skip "$f"; then
    grep -qE "^skip +$(printf '%s' "$f" | sed 's/[.[\*^$/]/\\&/g')  \(.+\)$" <<<"$listed" ||
      fail "bin/test skips $f in CI without saying why"
  else
    fail "$f is neither run nor skipped by bin/test in CI"
  fi
done <<<"$suites"

# A listing that found almost nothing would make the loops above vacuous. A
# floor, not the exact count, so adding a suite does not mean editing this.
[ "$count" -ge 20 ] || fail "found only $count suite(s); the listing is broken"

if [ "$fails" -eq 0 ]; then
  printf 'ok   all %d suites are run by CI through bin/test, or skipped with a reason\n' "$count"
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
