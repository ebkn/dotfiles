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
  guard_line=$(grep -n -E '^\. .*tmux-test-guard\.sh" \|\| exit 2$' "$f" | head -n 1 | cut -d: -f1)
  if [ -z "$guard_line" ]; then
    fail "$f is a tmux suite but does not source the guard (with || exit 2)"
    continue
  fi
  # And BEFORE anything that would act on the host when the guard refuses: a
  # trap registered above it runs its cleanup -- a bare `tmux kill-server` --
  # on the exit the guard itself causes.
  first_act=$(grep -n -E '^[[:space:]]*(trap |tmux )' "$f" | head -n 1 | cut -d: -f1)
  if [ -n "$first_act" ] && [ "$first_act" -lt "$guard_line" ]; then
    fail "$f registers a trap or runs tmux (line $first_act) before the guard (line $guard_line)"
  fi
done <<<"$suites"
# A listing that found almost nothing would make the loop above vacuous. A
# floor, not the exact count, so adding a suite does not mean editing this.
[ "$count" -ge 5 ] || fail "found only $count tmux suite(s); the listing is broken"
[ "$fails" -eq 0 ] && printf 'ok   all %d tmux suites source the guard before any trap or tmux call\n' "$count"

# bin/test-in-docker enrolls by a COPY of the regex above. If the two drift, a
# local run quietly stops running some suites and still prints "all N suite(s)
# passed". So it is run here, with docker stubbed to record what it was asked
# to run, and its list must be exactly the guarded suites found above.
stub=$(mktemp -d)
trap '/bin/rm -rf "$stub"' EXIT
cat >"$stub/docker" <<'EOF'
#!/bin/bash
# `docker build` succeeds; `docker run` records one argument per line. With
# DOCKER_EXEC set it then runs what follows the image name here, so the script
# that would run in the container -- the pass/fail tally -- is exercised too.
[ "$1" = run ] || exit 0
printf '%s\n' "$@" >"$DOCKER_ARGV"
[ -n "${DOCKER_EXEC:-}" ] || exit 0
while [ $# -gt 0 ] && [ "$1" != dotfiles-test ]; do shift; done
shift
exec "$@"
EOF
chmod +x "$stub/docker"
if PATH="$stub:$PATH" DOCKER_ARGV="$stub/argv" bash bin/test-in-docker >/dev/null 2>&1; then
  # Everything after the `bash -c` script's $0 is the suite list.
  ran=$(sed -n '/^test-in-docker$/,$p' "$stub/argv" | sed 1d | sort)
  want=$(printf '%s\n' "$suites" | grep -vxF bin/tmux-test-guard.test.sh | sed '/^$/d' | sort)
  if [ "$ran" = "$want" ]; then
    printf 'ok   test-in-docker runs exactly the %d guarded suites\n' "$count"
  else
    fail "test-in-docker's suite list differs from the guarded suites: $(diff <(printf '%s\n' "$want") <(printf '%s\n' "$ran") | tr '\n' ' ')"
  fi
  # Read-only, and no -t: the runner has no TERM, and a writable mount lets a
  # suite edit the checkout it is testing.
  grep -qx -- "$PWD:/work:ro" "$stub/argv" ||
    fail "test-in-docker does not mount the checkout read-only"
  if grep -qxE -- '-[a-z]*t[a-z]*' "$stub/argv"; then
    fail "test-in-docker allocates a tty, so TERM is set unlike on the runner"
  fi
else
  fail "test-in-docker failed with docker stubbed"
fi

# The tally, run for real through the stub. test-in-docker is the only way to
# run the tmux suites locally, and its exit status is what a caller -- an agent
# included -- believes. A broken `|| failed=...` would print a suite's FAIL and
# then "all N suite(s) passed", exit 0. The fixtures are given by absolute path,
# which the script inside resolves as the container would.
tally=$(mktemp -d)
trap '/bin/rm -rf "$stub" "$tally"' EXIT
printf 'exit 0\n' >"$tally/pass.test.sh"
printf 'exit 3\n' >"$tally/fail.test.sh"
# Passes only under zsh, so a .zsh suite run by bash fails the tally.
printf '[ -n "${ZSH_VERSION:-}" ]\n' >"$tally/only-zsh.test.zsh"
run_tally() {
  PATH="$stub:$PATH" DOCKER_ARGV="$stub/argv" DOCKER_EXEC=1 bash bin/test-in-docker "$@" 2>&1
}
if out=$(run_tally "$tally/pass.test.sh" "$tally/fail.test.sh" "$tally/only-zsh.test.zsh"); then
  fail "test-in-docker exited 0 with a failing suite: $out"
else
  printf 'ok   a failing suite makes test-in-docker exit non-zero\n'
fi
case "$out" in
  *"FAILED: $tally/fail.test.sh"$'\n'* | *"FAILED: $tally/fail.test.sh") printf 'ok   and it names exactly that suite\n' ;;
  *) fail "test-in-docker did not name the failing suite alone: $out" ;;
esac
case "$out" in
  *"suite(s) passed"*) fail "test-in-docker claimed a pass alongside a failure: $out" ;;
  *) printf 'ok   and claims no pass\n' ;;
esac
if out=$(run_tally "$tally/pass.test.sh" "$tally/only-zsh.test.zsh"); then
  case "$out" in
    *"all 2 suite(s) passed"*) printf 'ok   all passing (a .zsh suite run by zsh) exits 0 and counts them\n' ;;
    *) fail "test-in-docker passed without saying so: $out" ;;
  esac
else
  fail "test-in-docker failed passing suites (is a .zsh suite run by zsh?): $out"
fi

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
