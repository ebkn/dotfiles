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
suite z/only.test.zsh '[ -n "${ZSH_VERSION:-}" ] && touch "'"$marks"'/ran-under-zsh"'
# A tmux suite, recognised by the line every one of them carries.
suite t/tmux-x.test.sh '. "$(dirname "$0")/../bin/tmux-test-guard.sh" || exit 2'
# On bin/test's exclusion list by path.
suite root/.claude/hooks/git-guard.test.sh 'echo "ok   excluded ran"'
# Reads stdin: must get EOF, not the terminal, or the run hangs.
suite a/stdin.test.sh 'cat >/dev/null'
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.email=t@e -c user.name=t commit -q -m fixture
# Untracked, so never discovered -- like a suite nobody has added yet.
suite a/untracked.test.sh 'echo untracked'

# run <env...> -- bin/test in the fixture, as on a laptop unless overridden.
host=(GITHUB_ACTIONS=false TEST_CONTAINER_MARK="$work/no-such-file")
run() {
  (cd "$repo" && env "$@" bin/test) 2>&1
}
runargs() { # runargs <env assignment>... -- <args>...
  local envs=()
  while [ "$1" != -- ]; do
    envs+=("$1")
    shift
  done
  shift
  (cd "$repo" && env "${envs[@]}" bin/test "$@") 2>&1
}

# --- what it runs -------------------------------------------------------------
printf 'discovery\n'
list=$(runargs "${host[@]}" -- --list)
has "a tracked suite is listed to run" "$list" "run  a/pass.test.sh"
has "so is a zsh suite" "$list" "run  z/only.test.zsh"
has "an excluded suite is listed as skipped, with its reason" "$list" "skip root/.claude/hooks/git-guard.test.sh"
has "a tmux suite is skipped on a laptop" "$list" "skip t/tmux-x.test.sh"
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
  [ -e "$marks/$s" ] && ok "$s ran" || no "$s ran"
done
[ -e "$marks/ran-under-zsh" ] && ok "the zsh suite ran under zsh" || no "the zsh suite ran under zsh"
[ -e "$marks/tmux-x.test.sh" ] && no "a tmux suite did not run on a laptop" || ok "a tmux suite did not run on a laptop"
[ -e "$marks/git-guard.test.sh" ] && no "an excluded suite did not run" || ok "an excluded suite did not run"
[ -e "$marks/untracked.test.sh" ] && no "an untracked suite did not run" || ok "an untracked suite did not run"
has "the failing suite is named" "$out" "FAIL a/fail.test.sh"
has "with its own output" "$out" "boom from fail"
lacks "a passing suite's output stays out of a local run" "$out" "pass ran"
has "the summary counts both outcomes" "$out" "3 passed, 1 failed"
has "the tmux skip is said, with where to run them" "$out" "bin/test-in-docker"

# --- naming suites --------------------------------------------------------------
printf 'named suites\n'
out=$(runargs "${host[@]}" -- a/pass.test.sh z/only.test.zsh)
rc=$?
eq "named passing suites pass the run" "0" "$rc"
has "and only they are counted" "$out" "2 passed, 0 failed"
rm -f "$marks"/*
out=$(runargs "${host[@]}" -- root/.claude/hooks/git-guard.test.sh)
[ -e "$marks/git-guard.test.sh" ] && ok "an excluded suite runs when named" || no "an excluded suite runs when named"
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
[ $((SECONDS - started)) -lt 15 ] && ok "and is stopped, not waited out" || no "and is stopped, not waited out"
has "it is reported as timed out" "$out" "timed out"
has "with what it printed before it was stopped" "$out" "partial line"

# Two failing suites printing slowly at the same time: each block stays whole.
suite a/slow1.test.sh 'for i in 1 2 3; do echo "one-$i"; sleep 0.2; done; exit 1'
suite a/slow2.test.sh 'for i in 1 2 3; do echo "two-$i"; sleep 0.2; done; exit 1'
out=$(runargs "${host[@]}" -- a/slow1.test.sh a/slow2.test.sh)
has "one suite's lines are not interleaved with another's" "$out" "one-1
one-2
one-3"

printf 'GitHub Actions\n'
out=$(runargs GITHUB_ACTIONS=true TEST_CONTAINER_MARK="$work/no-such-file" -- a/pass.test.sh)
has "a passing suite's output is kept, folded" "$out" "::group::ok   a/pass.test.sh"
has "inside its group" "$out" "pass ran"
has "and the group is closed" "$out" "::endgroup::"

printf 'timings\n'
suite a/second.test.sh 'sleep 1.2'
out=$(runargs "${host[@]}" -- a/second.test.sh a/pass.test.sh)
has "a suite taking a second or more is in the time table" "$out" "a/second.test.sh"

# --- the listing itself ---------------------------------------------------------
printf 'listing\n'
mkdir -p "$work/not-a-repo/bin"
cp "$RUNNER" "$work/not-a-repo/bin/test"
out=$(cd "$work/not-a-repo" && env "${host[@]}" bin/test 2>&1)
rc=$?
[ "$rc" -ne 0 ] && ok "a failed listing fails the run" || no "a failed listing fails the run" "exit 0: $out"
lacks "and does not report a pass" "$out" "0 failed"

mkdir -p "$work/empty/bin"
cp "$RUNNER" "$work/empty/bin/test"
git -C "$work/empty" init -q
git -C "$work/empty" add -A
git -C "$work/empty" -c user.email=t@e -c user.name=t commit -q -m empty
out=$(cd "$work/empty" && env "${host[@]}" bin/test 2>&1)
rc=$?
[ "$rc" -ne 0 ] && ok "a listing with no suites fails the run" || no "a listing with no suites fails the run" "exit 0: $out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
