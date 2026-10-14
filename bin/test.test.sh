#!/usr/bin/env bash
#
# test.test.sh -- pins bin/test, the runner every suite goes through locally
# and in CI. See bin/test.md.
#
# A runner fails the way a lint gate does: by running less than it should and
# reporting green. So most cases here are about what it runs and what it
# counts -- against a throwaway repository of tiny suites, with the real GNU
# parallel -- and the rest about a failure never being lost on the way out:
# the failing suite's own output, a suite that hangs, a listing that fails.
#
# Each case sets the environment bin/test probes (GITHUB_ACTIONS and the
# container marker) explicitly, because this file itself runs on a laptop, in
# the container and in CI.
set -uo pipefail

RUNNER="$(cd "$(dirname "$0")" && pwd)/test"
command -v parallel >/dev/null || {
  echo "GNU parallel is required (see bin/test.md)"
  exit 1
}

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  printf 'ok   %s\n' "$1"
}
no() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1"
  [ $# -gt 1 ] && printf '     %s\n' "$2"
}
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "want=[$2] got=[$3]"; fi; }
yes() { # yes <label> <command...> -- the command must succeed
  local label=$1
  shift
  if "$@"; then ok "$label"; else no "$label"; fi
}
not() { # not <label> <command...> -- the command must fail
  local label=$1
  shift
  if "$@"; then no "$label"; else ok "$label"; fi
}
has() { case "$2" in *"$3"*) ok "$1" ;; *) no "$1" "does not contain [$3]: $2" ;; esac }
lacks() { case "$2" in *"$3"*) no "$1" "unexpectedly contains [$3]: $2" ;; *) ok "$1" ;; esac }

work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
marks="$work/marks"
mkdir -p "$marks"

# suite <path> <body> -- a fixture suite that leaves a mark when it runs.
suite() {
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s\n' "touch \"$marks/\$(basename \"\$0\")\"" "$2" >"$repo/$1"
}

repo="$work/repo"
mkdir -p "$repo/bin"
cp "$RUNNER" "$repo/bin/test"
suite a/pass.test.sh 'echo "ok   pass ran"'
suite a/fail.test.sh 'echo "FAIL boom from fail"; exit 1'
# Leaves a second mark only when zsh is what runs it.
# shellcheck disable=SC2016 # expanded by the fixture suite, not here
suite z/only.test.zsh '[ -n "${ZSH_VERSION:-}" ] && touch "'"$marks"'/ran-under-zsh"'
# A tmux suite, recognised by the line every one of them carries.
# shellcheck disable=SC2016 # the guard line, verbatim
suite t/tmux-x.test.sh '. "$(dirname "$0")/../bin/tmux-test-guard.sh" || exit 2'
# The fixture's own exclusion list, so these cases do not depend on what the
# real one happens to name.
printf '%s\n' '# a comment line' \
  'root/.claude/hooks/git-guard.test.sh|excluded on purpose by the fixture' >"$repo/bin/test.skip"
suite root/.claude/hooks/git-guard.test.sh 'echo "ok   excluded ran"'
# A path that is the tail of the excluded one: a substring match would skip it
# too, with the other suite's reason. Leaves no mark, so the run cases are
# unaffected.
mkdir -p "$repo/hooks"
printf 'exit 0\n' >"$repo/hooks/git-guard.test.sh"
# Reads stdin: must get EOF, not the terminal, or the run hangs.
suite a/stdin.test.sh 'cat >/dev/null'
# Records the job count it was handed.
# shellcheck disable=SC2016 # expanded by the fixture suite, not here
suite a/jobs.test.sh 'printf "%s" "${TEST_JOBS:-unset}" >"'"$marks"'/jobs-seen"'
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.email=t@e -c user.name=t commit -q -m fixture
# Untracked, so never discovered -- like a suite nobody has added yet.
suite a/untracked.test.sh 'echo untracked'

# run <env...> -- bin/test in the fixture, as on a laptop unless overridden.
host=(GITHUB_ACTIONS=false TEST_CONTAINER_MARK="$work/no-such-file")
run() {
  (cd "$repo" && env -u TEST_JOBS -u TEST_TIMEOUT "$@" bin/test) 2>&1
}
runargs() { # runargs <env assignment>... -- <args>...
  local envs=()
  while [ "$1" != -- ]; do
    envs+=("$1")
    shift
  done
  shift
  (cd "$repo" && env -u TEST_JOBS -u TEST_TIMEOUT "${envs[@]}" bin/test "$@") 2>&1
}

# --- what it runs -------------------------------------------------------------
printf 'discovery\n'
rm -f "$marks"/*
list=$(runargs "${host[@]}" -- --list)
eq "--list runs no suite" "" "$(ls "$marks")"
has "a tracked suite is listed to run" "$list" "run  a/pass.test.sh"
has "so is a zsh suite" "$list" "run  z/only.test.zsh"
has "an excluded suite is listed as skipped, with its reason" "$list" \
  "skip root/.claude/hooks/git-guard.test.sh  (excluded on purpose by the fixture)"
has "a suite whose path is the tail of an excluded one still runs" "$list" "run  hooks/git-guard.test.sh"
has "a tmux suite is skipped on a laptop, with where to run it" "$list" \
  "skip t/tmux-x.test.sh  (a tmux suite: bin/test-in-docker)"
lacks "an untracked suite is not discovered" "$list" "untracked"
ci_list=$(runargs GITHUB_ACTIONS=true TEST_CONTAINER_MARK="$work/no-such-file" -- --list)
has "a tmux suite runs in CI" "$ci_list" "run  t/tmux-x.test.sh"
: >"$work/dockerenv"
box_list=$(runargs GITHUB_ACTIONS=false TEST_CONTAINER_MARK="$work/dockerenv" -- --list)
has "and in a container" "$box_list" "run  t/tmux-x.test.sh"

printf 'a full run\n'
rm -f "$marks"/*
out=$(run "${host[@]}")
rc=$?
eq "a failing suite fails the run" "1" "$rc"
for s in pass.test.sh fail.test.sh only.test.zsh stdin.test.sh; do
  yes "$s ran" [ -e "$marks/$s" ]
done
yes "the zsh suite ran under zsh" [ -e "$marks/ran-under-zsh" ]
not "a tmux suite did not run on a laptop" [ -e "$marks/tmux-x.test.sh" ]
not "an excluded suite did not run" [ -e "$marks/git-guard.test.sh" ]
not "an untracked suite did not run" [ -e "$marks/untracked.test.sh" ]
has "the failing suite is named" "$out" "FAIL a/fail.test.sh"
has "with its own output" "$out" "boom from fail"
lacks "a passing suite's output stays out of a local run" "$out" "pass ran"
has "the summary counts both outcomes" "$out" "5 passed, 1 failed"
has "the tmux skip is said, with where to run them" "$out" "bin/test-in-docker"
has "the failed suites are listed at the end" "$out" "failed:
  a/fail.test.sh"
# The figure bin/test settled on, not just one the caller set: a sharded suite
# would otherwise fall back to every CPU on top of bin/test's own jobs.
jobs_seen=$(cat "$marks/jobs-seen" 2>/dev/null)
case "$jobs_seen" in
  '' | unset | *[!0-9]*) no "a suite is handed the job count bin/test chose" "got [$jobs_seen]" ;;
  *) ok "a suite is handed the job count bin/test chose ($jobs_seen)" ;;
esac

# --- naming suites --------------------------------------------------------------
printf 'named suites\n'
out=$(runargs "${host[@]}" -- a/pass.test.sh z/only.test.zsh)
rc=$?
eq "named passing suites pass the run" "0" "$rc"
has "and only they are counted" "$out" "2 passed, 0 failed"
rm -f "$marks"/*
out=$(runargs "${host[@]}" -- root/.claude/hooks/git-guard.test.sh)
yes "an excluded suite runs when named" [ -e "$marks/git-guard.test.sh" ]
out=$(runargs "${host[@]}" -- a/no-such.test.sh)
rc=$?
eq "a named suite that does not exist fails" "1" "$rc"
has "and is named" "$out" "a/no-such.test.sh"

# --- nothing is lost on the way out ---------------------------------------------
printf 'failures\n'
suite a/hang.test.sh 'echo "partial line"; sleep 30'
started=$SECONDS
out=$(runargs "${host[@]}" TEST_TIMEOUT=1 -- a/hang.test.sh)
rc=$?
eq "a suite past TEST_TIMEOUT fails the run" "1" "$rc"
yes "and is stopped, not waited out" [ $((SECONDS - started)) -lt 15 ]
has "it is reported as timed out" "$out" "timed out"
has "with what it printed before it was stopped" "$out" "partial line"

# A suite parallel never starts. HUP to parallel is its documented way to stop
# starting jobs ($PARALLEL_PID is the parallel running this job, not any
# outer one); parallel itself then still exits 0, which is exactly why the
# verdict is checked against the job log.
# shellcheck disable=SC2016 # expanded by the fixture suite, not here
suite a/stopper.test.sh 'kill -HUP "$PARALLEL_PID"; sleep 0.5'
suite a/never.test.sh ':'
rm -f "$marks"/*
out=$(runargs "${host[@]}" TEST_JOBS=1 -- a/stopper.test.sh a/never.test.sh)
rc=$?
not "a suite parallel never started did not run" [ -e "$marks/never.test.sh" ]
eq "a suite that never ran fails the run" "1" "$rc"
has "and is reported as never run" "$out" "1 of 2 suite(s) never ran"

# Two failing suites printing slowly at the same time: each block stays whole.
# shellcheck disable=SC2016 # expanded by the fixture suite, not here
suite a/slow1.test.sh 'for i in 1 2 3; do echo "one-$i"; sleep 0.2; done; exit 1'
# shellcheck disable=SC2016 # expanded by the fixture suite, not here
suite a/slow2.test.sh 'for i in 1 2 3; do echo "two-$i"; sleep 0.2; done; exit 1'
out=$(runargs "${host[@]}" -- a/slow1.test.sh a/slow2.test.sh)
has "one suite's lines are not interleaved with another's" "$out" "one-1
one-2
one-3"

printf 'GitHub Actions\n'
out=$(runargs GITHUB_ACTIONS=true TEST_CONTAINER_MARK="$work/no-such-file" -- a/pass.test.sh)
has "a passing suite's output is kept, inside a closed group" "$out" "::group::ok   a/pass.test.sh
ok   pass ran
::endgroup::"

printf 'timings\n'
suite a/second.test.sh 'sleep 1.2'
out=$(runargs "${host[@]}" -- a/second.test.sh a/pass.test.sh)
table=${out#*--- time per suite (1 s or more) ---}
if [ "$table" = "$out" ]; then
  no "the run ends with a time table"
else
  ok "the run ends with a time table"
  has "a suite taking a second or more is in it" "$table" "s  a/second.test.sh"
  lacks "a sub-second suite is not" "$table" "a/pass.test.sh"
fi

printf 'settings\n'
rm -f "$marks"/*
out=$(runargs "${host[@]}" TEST_TIMEOUT=0 -- a/pass.test.sh)
rc=$?
# parallel takes --timeout 0 as no timeout at all.
eq "TEST_TIMEOUT=0 is refused" "1" "$rc"
has "and named" "$out" "positive integers: 0"
out=$(runargs "${host[@]}" TEST_JOBS=many -- a/pass.test.sh)
rc=$?
eq "a TEST_JOBS that is not a number is refused" "1" "$rc"
not "and nothing runs" [ -e "$marks/pass.test.sh" ]

printf 'exclusions\n'
cp "$repo/bin/test.skip" "$work/skip.orig"
printf '%s\n' 'a/gone.test.sh|a suite deleted since' >>"$repo/bin/test.skip"
out=$(runargs "${host[@]}" -- --list)
rc=$?
eq "an exclusion naming no tracked suite fails --list" "1" "$rc"
has "and names it" "$out" "a/gone.test.sh"
# The fixture has a failing suite, so a bare run exits 1 anyway: what shows the
# refusal is that it names the entry and runs nothing.
rm -f "$marks"/*
out=$(run "${host[@]}")
rc=$?
eq "and fails a bare run" "1" "$rc"
has "naming the entry" "$out" "a/gone.test.sh"
eq "before running any suite" "" "$(ls "$marks")"
cp "$work/skip.orig" "$repo/bin/test.skip"

# An entry with no reason, or an empty one, is refused too: otherwise the first
# is skipped with its own path for a reason, and the second not skipped at all.
for entry in 'a/pass.test.sh' 'a/pass.test.sh|'; do
  printf '%s\n' "$entry" >>"$repo/bin/test.skip"
  out=$(runargs "${host[@]}" -- --list)
  rc=$?
  eq "an entry without a reason is refused: [$entry]" "1" "$rc"
  has "and named: [$entry]" "$out" "no reason"
  cp "$work/skip.orig" "$repo/bin/test.skip"
done

# --- the listing itself ---------------------------------------------------------
printf 'listing\n'
mkdir -p "$work/not-a-repo/bin"
cp "$RUNNER" "$work/not-a-repo/bin/test"
out=$(cd "$work/not-a-repo" && env "${host[@]}" bin/test 2>&1)
rc=$?
yes "a failed listing fails the run" [ "$rc" -ne 0 ]
lacks "and does not report a pass" "$out" "0 failed"

mkdir -p "$work/empty/bin"
cp "$RUNNER" "$work/empty/bin/test"
git -C "$work/empty" init -q
git -C "$work/empty" add -A
git -C "$work/empty" -c user.email=t@e -c user.name=t commit -q -m empty
out=$(cd "$work/empty" && env "${host[@]}" bin/test 2>&1)
rc=$?
yes "a listing with no suites fails the run" [ "$rc" -ne 0 ]

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
