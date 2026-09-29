#!/bin/bash
#
# tmux-test-guard.test.sh
#
# Pins the two halves of keeping tmux suites off the developer's machine:
#
# (1) Enrollment: every tmux suite sources bin/tmux-test-guard.sh -- each
#     bin/tmux-*.test.sh, and any suite that invokes `tmux ... new-session` or
#     `kill-server` outside a comment. "Remember to add the guard" is the same
#     kind of rule as "remember to unset TMUX", which is the one that already
#     failed. Matching the bare words would be wrong both ways: two tmux-*
#     suites only see them as text in a stub's call log, and a zsh suite quotes
#     them in a comment and an expected string without running tmux.
# (2) Refusal: outside a container and outside CI, sourcing the guard stops the
#     caller with exit 2 before anything after it runs.
#
# Static and tmux-free itself, so it is safe to run anywhere.

set -eo pipefail

cd "$(dirname "$0")/.."
fails=0
fail() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

# Listings that fail must not read as "there are no tmux suites".
if ! named=$(git ls-files -- 'bin/tmux-*.test.sh'); then
  fail "could not list bin/tmux-*.test.sh"
fi
if ! invokers=$(git grep -l -E '^[^#]*tmux[^#]*(new-session|kill-server)' -- '*.test.sh' '*.test.zsh'); then
  fail "could not list the suites that invoke tmux"
fi
suites=$(printf '%s\n%s\n' "$named" "$invokers" | sort -u)
count=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Matches bin/tmux-*.test.sh by name, and would pass itself: the pattern
  # below is in its own text.
  [ "$f" = bin/tmux-test-guard.test.sh ] && continue
  count=$((count + 1))
  # The sourcing line, the same match bin/test-in-docker enrolls by.
  grep -q -E '^\. .*tmux-test-guard\.sh" \|\| exit 2$' "$f" ||
    fail "$f is a tmux suite but does not source the guard (with || exit 2)"
done <<<"$suites"
# A listing that found almost nothing would make the loop above vacuous. A
# floor, not the exact count, so adding a suite does not mean editing this.
[ "$count" -ge 5 ] || fail "found only $count tmux suite(s); the listing is broken"
[ "$fails" -eq 0 ] && printf 'ok   all %d tmux suites source the guard\n' "$count"

# Refusal. Only checkable where the guard is meant to refuse: in a container
# /.dockerenv exists and it rightly lets the caller through.
if [ ! -f /.dockerenv ]; then
  set +e
  out=$(env -u GITHUB_ACTIONS bash -c '. bin/tmux-test-guard.sh; echo REACHED' 2>&1)
  status=$?
  set -e
  if [ "$status" -eq 2 ] && [ "${out#*REACHED}" = "$out" ]; then
    printf 'ok   outside a container and CI, the guard exits 2 before the caller continues\n'
  else
    fail "outside a container and CI the guard let the caller run (exit $status): $out"
  fi
fi

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
