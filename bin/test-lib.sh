# shellcheck shell=bash
#
# test-lib.sh -- helpers a *.test.sh suite sources. bin/testing.md, rules 5-6.
#
#   . "$(dirname "$0")/test-lib.sh" || exit 2     (from bin/; adjust elsewhere)
#
# Output contract (rule 5): one line per check, `ok   <what>` or `FAIL <what>`,
# details indented five spaces under a FAIL, then a blank line and
# `N passed, M failed`. Exit 0 if and only if nothing failed -- and a run that
# checked nothing fails too, so a broken filter or an early return cannot pass.
#
# Two ways to use it, mixable:
#   - checks at top level, then `test_summary` as the last line;
#   - `test_*` functions, then `run_tests` as the last line: each function runs
#     in a subshell of its own (a cd or a variable cannot leak into the next),
#     in the order written, and only those containing $TEST_FILTER.
# Mixed, the top level's checks count in the same verdict, and what it set up
# (test_tmpdir, track_pid) lasts through every case -- rule 3's shape.
#
# Any condition is checked as `assert_status "<what>" 0 <cmd...>`. Moving a
# suite with a counter of its own here: see bin/testing.md rule 6 first.
#
# Works under `set -u` and `set -e` alike. Under `set -e` a failing command in
# a case ends that case, which is a FAIL like an `exit` non-zero; without it,
# the status a case function returns is not a verdict.
#
# test_tmpdir and track_pid own the EXIT trap. A suite that sets its own trap
# afterwards replaces their cleanup, and one that set a trap before has it
# replaced: call your cleanup from a function and register what it removes
# with these instead. The same holds inside a case. The verdict never depends
# on the trap: every check has reported by the time it runs.
#
# A sourced fragment (CLAUDE.md, Shell Script Conventions): bash 3.2, no
# shebang, no `set`, and named inline in bin/lint-shell. Pinned by
# bin/test-lib.test.sh, which runs it under /bin/bash.

_TL_PIDS=''
_TL_DIRS=''
# Every check appends one letter, p or f, to this file, and test_summary counts
# them. A file and not a variable, so a check made in a subshell counts too --
# a run_tests case, a pipeline, a $( ) -- and one that exits, dies under set -e
# or replaces the EXIT trap has already reported. Named here, created by the
# first check and removed by test_summary, so a suite that only uses
# next_second or wait_until leaves nothing behind. $$ is the suite's pid in
# its subshells too; a file left by a dead suite with the same pid is cleared.
_TL_TALLY=${TMPDIR:-/tmp}/test-lib-tally.$$
if [ -e "$_TL_TALLY" ]; then rm -f "$_TL_TALLY"; fi
# The suite file, absolute: run_tests reads its cases from it, and bin/test
# starts suites by relative path, which a later cd would break.
case "$0" in
  /*) _TL_SELF=$0 ;;
  *) _TL_SELF=$PWD/$0 ;;
esac

_tl_ok() {
  printf 'ok   %s\n' "$1"
  printf p >>"$_TL_TALLY"
}
# _tl_bad <what> [<label> <value>]... -- a FAIL line, then each value under
# its label, every line of a multi-line value indented to the same column.
_tl_bad() {
  local line first
  printf 'FAIL %s\n' "$1"
  shift
  while [ $# -ge 2 ]; do
    first=yes
    while IFS= read -r line; do
      if [ "$first" = yes ]; then
        printf '     %-5s %s\n' "$1:" "$line"
        first=no
      else
        printf '           %s\n' "$line"
      fi
    done <<<"$2"
    shift 2
  done
  printf f >>"$_TL_TALLY"
}

# assert_eq <what> <want> <got>
assert_eq() {
  if [ "$2" = "$3" ]; then _tl_ok "$1"; else _tl_bad "$1" want "$2" got "$3"; fi
}

# assert_contains <what> <text> <part> -- a builtin match, no grep per check.
assert_contains() {
  case "$2" in
    *"$3"*) _tl_ok "$1" ;;
    *) _tl_bad "$1" want "contains: $3" got "$2" ;;
  esac
}

# assert_not_contains <what> <text> <part>
assert_not_contains() {
  case "$2" in
    *"$3"*) _tl_bad "$1" want "lacks: $3" got "$2" ;;
    *) _tl_ok "$1" ;;
  esac
}

# assert_status <what> <want status> <command...> -- run the command, compare
# its exit status, and show what it printed when the status is wrong. The
# status is taken in an `if`, so a caller's set -e does not end the suite on
# the very failure being asserted.
assert_status() {
  local what=$1 want=$2 out status
  shift 2
  if out=$("$@" 2>&1); then status=0; else status=$?; fi
  if [ "$status" = "$want" ]; then
    _tl_ok "$what"
  else
    _tl_bad "$what" want "status $want" got "status $status" out "$out"
  fi
}

# wait_until <seconds> <command...> -- run the command every 0.05 s until it
# succeeds (return 0) or <seconds> have been slept (return 1); 2 and a message
# when <seconds> is not a number. Rule 1: the deadline is only reached when
# the test is failing, so a generous one costs nothing on a green run.
# <seconds> may have one decimal (0.5). The deadline counts the sleeps, not the
# command's own time, so a slow command stretches it.
wait_until() {
  local secs=$1 whole frac=0 n i=0
  shift
  case "$secs" in
    '' | *[!0-9.]* | *.*.* | .*)
      printf 'wait_until: not a number of seconds: %s\n' "$secs" >&2
      return 2
      ;;
  esac
  whole=${secs%%.*}
  case "$secs" in *.*)
    frac=${secs#*.}
    frac=${frac:0:1}
    ;;
  esac
  # 10#: a leading zero would otherwise read as octal (08 is an error).
  n=$((10#$whole * 20 + 10#${frac:-0} * 2))
  while :; do
    if "$@"; then return 0; fi
    i=$((i + 1))
    if [ "$i" -gt "$n" ]; then return 1; fi
    sleep 0.05
  done
}

# next_second <epoch> -- return once the clock has passed <epoch>'s second, for
# a case that needs two one-second stamps to differ: half a second on average,
# where `sleep 1` always paid the whole one. A stamp that is not a number waits
# the full second, so a broken read cannot remove the wait the case depends on;
# the wait is bounded at 40 polls (2-3 s with the date each one runs), so a
# stamp from the future cannot hang the suite.
next_second() {
  local i=0
  case "$1" in
    '' | *[!0-9]*)
      sleep 1
      return 0
      ;;
  esac
  while [ "$(date +%s)" -le "$1" ] && [ $((i += 1)) -le 40 ]; do sleep 0.05; done
}

# test_tmpdir -- make a scratch directory, $TEST_TMPDIR, removed on exit along
# with every process registered with track_pid. Inside a run_tests case the
# directory and the processes are that case's, cleaned up when it ends.
test_tmpdir() {
  TEST_TMPDIR=$(mktemp -d) || {
    printf 'test_tmpdir: mktemp failed\n' >&2
    exit 1
  }
  _TL_DIRS="$_TL_DIRS $TEST_TMPDIR"
  trap _tl_exit EXIT
}

# track_pid <pid> -- kill this process when the suite (or the case) exits.
track_pid() {
  _TL_PIDS="$_TL_PIDS $1"
  trap _tl_exit EXIT
}

_tl_exit() {
  local p d
  for p in $_TL_PIDS; do
    # Disowned first: killing a background job of this shell otherwise makes
    # bash print "Terminated" after the summary line, which is then not last.
    # Each may fail -- a pid that already exited, or one that is not this
    # shell's job -- and must not stop the cleanup under set -e.
    disown "$p" 2>/dev/null || :
    kill "$p" 2>/dev/null || :
  done
  for d in $_TL_DIRS; do
    # A case may have left a directory unwritable (chmod 500, to test a
    # permission failure); rm alone then fails, and under set -e stops here.
    chmod -R u+rwx "$d" 2>/dev/null || :
    rm -rf "$d" || :
  done
  return 0
}

# test_summary -- print the summary line and exit with the verdict.
test_summary() {
  local tally='' rest pass fail
  if [ -e "$_TL_TALLY" ]; then read -r tally <"$_TL_TALLY" || :; fi
  rm -f "$_TL_TALLY"
  rest=${tally//f/}
  pass=${#rest}
  rest=${tally//p/}
  fail=${#rest}
  if [ $((pass + fail)) -eq 0 ]; then
    printf 'FAIL nothing was checked%s\n' "${TEST_FILTER:+ (TEST_FILTER=$TEST_FILTER)}"
    fail=1
  fi
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  if [ "$fail" -eq 0 ]; then exit 0; fi
  exit 1
}

# run_tests -- run the suite's test_* functions, then test_summary. Found in
# the suite file itself, which is what gives the written order; a function the
# file defines some other way is not found.
run_tests() {
  local names fn status errexit=
  names=$(grep -oE '^test_[A-Za-z0-9_]+[[:space:]]*\(\)' "$_TL_SELF" | tr -d ' ()') || names=''
  for fn in $names; do
    case "$fn" in *"${TEST_FILTER:-}"*) ;; *) continue ;; esac
    # Found in the file but not defined: written below the run_tests line,
    # which exits before reaching it. Skipped quietly, a case added at the
    # end of a suite would never run and the suite would stay green.
    if ! declare -F "$fn" >/dev/null; then
      _tl_bad "$fn is defined after run_tests, so it never ran"
      continue
    fi
    # Not in an `if`: a subshell in a condition runs with set -e off whatever
    # the suite asked for, so the case would carry on past a failing command.
    # Off here instead, around the case only, and back on inside it.
    case $- in *e*) errexit=yes ;; *) errexit= ;; esac
    set +e
    (
      # The case's own resources only: what the top level set up outlives it.
      _TL_PIDS='' _TL_DIRS=''
      trap _tl_exit EXIT
      if [ -n "$errexit" ]; then set -e; fi
      "$fn"
      # Without set -e a function's return status is not a verdict -- one
      # ending in a false `[ ]` returns 1 -- but an `exit` is: it never reaches
      # this line. Under set -e a failing command exits before it, too.
      exit 0
    )
    status=$?
    if [ -n "$errexit" ]; then set -e; fi
    if [ "$status" -ne 0 ]; then _tl_bad "$fn exited $status"; fi
  done
  test_summary
}
