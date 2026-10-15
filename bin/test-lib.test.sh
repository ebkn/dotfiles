#!/bin/bash
#
# test-lib.test.sh -- pins bin/test-lib.sh, the helpers suites source.
#
# Not written with the library: a broken assert_eq would then judge itself.
# Each case runs a small fixture suite that sources the library, in a process
# of its own, and checks what it printed and how it exited -- the two things a
# runner and a reader see. Fixtures run under /bin/bash where it exists, which
# is 3.2 on macOS: the library is sourced by #!/bin/bash suites, and bin/test
# starts every suite with PATH's bash, which would never exercise 3.2.
#
# Run: bash bin/test-lib.test.sh   (exit 0 = pass)

set -u

lib="$(cd "$(dirname "$0")" && pwd)/test-lib.sh"
sh=/bin/bash
[ -x "$sh" ] || sh=bash
WORK=$(mktemp -d)
export WORK
trap 'rm -rf "$WORK"' EXIT
nl=$'\n'

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  shift
  # Every line indented, a fixture's own ok lines included, so they cannot
  # be counted as this suite's.
  for l in "$@"; do printf '%s\n' "$l" | sed 's/^/     /'; done
  fails=$((fails + 1))
}

# A filter in the caller's environment would reach every fixture.
unset TEST_FILTER

# suite <name> [set options] <<'EOF' -- write a fixture suite, sourcing the
# library, from stdin. The fixtures reach this run's scratch dir as $WORK.
# By default under `set -euo pipefail`, the strictest a caller uses: the suites
# that source the library run under `set -u` or `set -e`, and an unguarded
# variable or an unchecked status in it shows only there otherwise.
suite() {
  {
    printf 'set %s\n. %q || exit 2\n' "${2:--euo pipefail}" "$lib"
    cat
  } >"$WORK/$1"
}
# run <name> -- run it from $WORK; sets $out (stdout and stderr) and $status.
run() {
  out=$(cd "$WORK" && "$sh" "$WORK/$1" 2>&1)
  status=$?
}
# expect <desc> <want status> <pattern the whole output must match>
expect() {
  # shellcheck disable=SC2254 # the argument is a pattern on purpose
  case "$out" in
    $3) if [ "$status" = "$2" ]; then pass "$1"; else fail "$1" "status $status, want $2" "$out"; fi ;;
    *) fail "$1" "output did not match: $3" "$out" ;;
  esac
}

# --- assertions and the summary ------------------------------------------------

suite asserts.sh <<'EOF'
assert_eq "equal" a a
assert_eq "unequal" a b
assert_contains "contains" "hello world" "lo w"
assert_contains "lacks" "hello" "xyz"
assert_not_contains "absent" "hello" "xyz"
assert_not_contains "present" "hello" "ell"
test_summary
EOF
run asserts.sh
expect "each assertion prints one ok or FAIL line, in order" 1 \
  "ok   equal${nl}FAIL unequal${nl}*ok   contains${nl}FAIL lacks${nl}*ok   absent${nl}FAIL present${nl}*"
expect "a FAIL carries want and got, indented under it" 1 \
  "*FAIL unequal${nl}     want: a${nl}     got:  b${nl}*"
expect "a failed contains says what it wanted to find" 1 "*FAIL lacks${nl}     want: contains: xyz${nl}*"
expect "a failed not-contains says what it wanted absent" 1 "*FAIL present${nl}     want: lacks: ell${nl}*"
expect "the output ends with a blank line and the counts; a failure exits 1" 1 \
  "*FAIL present*${nl}${nl}3 passed, 3 failed"

suite multiline.sh <<'EOF'
assert_eq "lines" "x" "$(printf 'one\ntwo')"
test_summary
EOF
run multiline.sh
expect "every line of a multi-line got is indented" 1 \
  "*     got:  one${nl}           two${nl}*"

suite green.sh <<'EOF'
assert_eq "one" 1 1
test_summary
EOF
run green.sh
expect "all passing exits 0" 0 "*1 passed, 0 failed"

suite empty.sh <<'EOF'
test_summary
EOF
run empty.sh
expect "a run that checked nothing fails, rather than passing vacuously" 1 \
  "*FAIL nothing was checked*"

suite status.sh <<'EOF'
assert_status "exit 3" 3 sh -c 'exit 3'
assert_status "exit 0 expected" 0 sh -c 'echo said this; exit 2'
test_summary
EOF
run status.sh
expect "assert_status compares the exit status" 1 "ok   exit 3${nl}FAIL exit 0 expected*"
expect "and shows the status it wanted and what the command printed" 1 \
  "*FAIL exit 0 expected${nl}     want: status 0${nl}     got:  status 2${nl}     out:  said this${nl}*"

# --- run_tests ------------------------------------------------------------------

suite cases.sh "-uo pipefail" <<'EOF'
test_b() { assert_eq "b ran" 1 1; }
test_a() { assert_eq "a ran" 1 1; cd /; leaked=yes; }
test_c() { [ -z "${leaked:-}" ] && assert_eq "c sees no cd or variable from a" "$WORK" "$PWD"; }
helper() { assert_eq "helper ran" 1 2; }
test_ends_false() { assert_eq "a false last command" 1 1; [ 1 = 2 ]; }
run_tests
EOF
run cases.sh
expect "run_tests runs every test_ function, in the order written" 0 \
  "ok   b ran${nl}ok   a ran${nl}ok   c sees no cd or variable from a${nl}*"
expect "and no other function" 0 "*${nl}4 passed, 0 failed"
expect "without set -e, a false last command is not a failure" 0 "*ok   a false last command${nl}${nl}*"

# Under set -e the suite asked for a failing command to end things: in a case,
# that is the case failing, and the rest still run.
suite errexit.sh <<'EOF'
test_false() { assert_eq "before the false" 1 1; [ 1 = 2 ]; assert_eq "never reached" 1 2; }
test_next() { assert_eq "the next case runs" 1 1; }
test_false_again() { [ 1 = 2 ]; assert_eq "never reached either" 1 2; }
run_tests
EOF
run errexit.sh
expect "under set -e a failing command ends its case as a FAIL, in every case" 1 \
  "ok   before the false${nl}FAIL test_false exited 1${nl}ok   the next case runs${nl}FAIL test_false_again exited 1${nl}${nl}2 passed, 2 failed"

# A check inside a subshell -- a pipeline, a ( ), a $( ) -- counts like any
# other, at the top level as in a case. It once counted only in a case, and a
# top-level FAIL in a pipeline printed and then exited 0.
suite subshell.sh <<'EOF'
assert_eq "top" 1 1
echo x | while read -r v; do assert_eq "in a pipeline" a "$v"; done
test_sub() { ( assert_eq "in a subshell" a b ); }
run_tests
EOF
run subshell.sh
expect "a check in a subshell counts, at the top level and in a case" 1 "*${nl}1 passed, 2 failed"

# A case written below run_tests is found in the file but never defined, since
# run_tests exits first. Skipped quietly, it would never run.
suite late.sh <<'EOF'
test_early() { assert_eq "early" 1 1; }
run_tests
test_late() { assert_eq "late" 1 1; }
EOF
run late.sh
expect "a case below run_tests is a FAIL, not skipped" 1 "*FAIL test_late is defined after run_tests, so it never ran*"

suite crash.sh <<'EOF'
test_dies() { assert_eq "before" 1 1; exit 4; }
test_after() { assert_eq "after" 1 1; }
run_tests
EOF
run crash.sh
expect "a test function that exits non-zero is a FAIL, and the rest still run" 1 \
  "*FAIL test_dies exited 4*ok   after*2 passed, 1 failed"

# A case that sets its own EXIT trap -- for its own cleanup -- must not take
# the verdict with it: the counts once came back only through the library's
# trap, and this printed a FAIL and exited 0.
suite owntrap.sh <<'EOF'
test_own_trap() {
  trap 'rm -f "$WORK/nonexistent"' EXIT
  assert_eq "this one fails" a b
}
test_passes() { assert_eq "this one passes" 1 1; }
run_tests
EOF
run owntrap.sh
expect "a case with an EXIT trap of its own still counts" 1 "*${nl}1 passed, 1 failed"

# Top-level checks and resources around run_tests, rule 3's shape: build once,
# then cases. The top level's FAIL counts, and its directory and process are
# still there for every case.
suite mixed.sh <<'EOF'
test_tmpdir
sleep 30 >/dev/null 2>&1 &
track_pid $!
held=$!
assert_eq "a top-level check that fails" a b
test_one() { assert_eq "one" 1 1; }
test_two() {
  assert_eq "the suite's directory outlives a case" yes "$([ -d "$TEST_TMPDIR" ] && echo yes || echo no)"
  assert_eq "the suite's process outlives a case" yes "$(kill -0 "$held" 2>/dev/null && echo yes || echo no)"
}
run_tests
EOF
run mixed.sh
expect "top-level checks and run_tests share one verdict" 1 "*${nl}3 passed, 1 failed"
expect "and the suite's resources survive its cases" 1 \
  "*ok   the suite's directory outlives a case${nl}ok   the suite's process outlives a case${nl}*"

# bin/test starts suites by relative path, and a suite may cd before
# run_tests; the file it reads its cases from must still be found.
suite relcd.sh <<'EOF'
cd /
test_found() { assert_eq "found after a cd" 1 1; }
run_tests
EOF
out=$(cd "$WORK" && "$sh" relcd.sh 2>&1)
status=$?
expect "run_tests finds the suite started by a relative path after a cd" 0 "ok   found after a cd${nl}*"

suite filter.sh <<'EOF'
test_alpha() { assert_eq alpha 1 1; }
test_beta() { assert_eq beta 1 1; }
run_tests
EOF
out=$(cd "$WORK" && TEST_FILTER=bet "$sh" "$WORK/filter.sh" 2>&1)
status=$?
expect "TEST_FILTER runs only the matching functions" 0 "ok   beta${nl}*1 passed, 0 failed"

out=$(cd "$WORK" && TEST_FILTER=nomatch "$sh" "$WORK/filter.sh" 2>&1)
status=$?
expect "a filter matching nothing fails rather than passing empty" 1 "*FAIL nothing was checked*"

# --- wait_until -------------------------------------------------------------------

suite wait.sh <<'EOF'
start=$SECONDS
(
  sleep 0.3
  : >flag
) &
if wait_until 5 test -e flag; then assert_eq "condition met" 1 1; else assert_eq "condition met" 0 1; fi
assert_eq "returned long before a 5 s deadline" yes "$([ $((SECONDS - start)) -le 2 ] && echo yes || echo no)"
start=$SECONDS
if wait_until 1 false; then :; fi
assert_eq "a whole-second deadline is waited out" yes "$([ $((SECONDS - start)) -ge 1 ] && [ $((SECONDS - start)) -le 4 ] && echo yes || echo no)"
start=$SECONDS
if wait_until 0.5 false; then assert_eq "deadline" 1 0; else assert_eq "deadline" 1 1; fi
assert_eq "gave up near its deadline" yes "$([ $((SECONDS - start)) -le 2 ] && echo yes || echo no)"
(
  sleep 0.2
  : >flag2
) &
if wait_until 0.9 test -e flag2; then assert_eq "a fractional deadline is waited for" 1 1; else assert_eq "a fractional deadline is waited for" 0 1; fi
assert_status "a deadline that is not a number is refused" 2 wait_until soon true
assert_status "a leading zero is decimal, not octal" 0 wait_until 08 true
test_summary
EOF
run wait.sh
expect "wait_until returns as soon as the command succeeds" 0 \
  "ok   condition met${nl}ok   returned long before a 5 s deadline${nl}ok   a whole-second deadline is waited out${nl}*"
expect "and fails at its deadline, which may be fractional" 0 \
  "*ok   deadline${nl}ok   gave up near its deadline${nl}ok   a fractional deadline is waited for${nl}ok   a deadline that is not a number is refused${nl}ok   a leading zero is decimal, not octal${nl}*"

# --- next_second -------------------------------------------------------------------

suite second.sh <<'EOF'
now=$(date +%s)
next_second "$now"
assert_eq "the clock has passed the stamp" yes "$([ "$(date +%s)" -gt "$now" ] && echo yes || echo no)"
start=$SECONDS
next_second "$((now + 30))"
assert_eq "a stamp from the future does not hang" yes "$([ $((SECONDS - start)) -le 10 ] && echo yes || echo no)"
start=$(date +%s)
next_second ""
assert_eq "an unreadable stamp waits a full second" yes "$([ "$(date +%s)" -gt "$start" ] && echo yes || echo no)"
start=$SECONDS
for _ in 1 2 3; do next_second "$((now - 60))"; done
assert_eq "a stamp already passed costs nothing" yes "$([ $((SECONDS - start)) -le 1 ] && echo yes || echo no)"
test_summary
EOF
run second.sh
expect "next_second waits for the clock to pass the stamp, bounded, never vanishing" 0 \
  "ok   the clock has passed the stamp${nl}ok   a stamp from the future does not hang${nl}ok   an unreadable stamp waits a full second${nl}ok   a stamp already passed costs nothing${nl}*"

# --- test_tmpdir and track_pid --------------------------------------------------------

suite tmp.sh <<'EOF'
test_tmpdir
printf '%s\n' "$TEST_TMPDIR" >"$WORK/tmpdir"
sleep 30 >/dev/null 2>&1 &
track_pid $!
printf '%s\n' "$!" >"$WORK/pid"
assert_eq "TEST_TMPDIR is a directory" yes "$([ -d "$TEST_TMPDIR" ] && echo yes || echo no)"
test_summary
EOF
run tmp.sh
# The whole output: killing a tracked child once printed a job notice
# ("Terminated") after the summary line.
expect "test_tmpdir makes a directory, and the output ends with the summary" 0 \
  "ok   TEST_TMPDIR is a directory${nl}${nl}1 passed, 0 failed"
d=$(cat "$WORK/tmpdir" 2>/dev/null)
if [ -n "$d" ] && [ ! -e "$d" ]; then
  pass "and removes it on exit"
else
  fail "and removes it on exit" "still there: $d"
fi
p=$(cat "$WORK/pid" 2>/dev/null)
if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then
  pass "a tracked pid is killed on exit"
else
  [ -n "$p" ] && kill "$p" 2>/dev/null
  fail "a tracked pid is killed on exit" "pid ${p:-missing} still running"
fi

# track_pid on its own sets the cleanup up too: a suite that tracks a server
# needs no scratch directory.
suite pidonly.sh <<'EOF'
sleep 30 >/dev/null 2>&1 &
track_pid $!
printf '%s\n' "$!" >"$WORK/pid2"
assert_eq "tracked" 1 1
test_summary
EOF
run pidonly.sh
expect "track_pid alone: a green run" 0 "ok   tracked${nl}${nl}1 passed, 0 failed"
p=$(cat "$WORK/pid2" 2>/dev/null)
if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then
  pass "track_pid alone kills the process on exit"
else
  [ -n "$p" ] && kill "$p" 2>/dev/null
  fail "track_pid alone kills the process on exit" "pid ${p:-missing} still running"
fi

# Pids a suite tracks are not all live jobs of its own shell: one may have
# exited already, or belong to a daemon (a tmux server). Under set -e the
# cleanup once stopped at the first of those -- exit 1 after a green summary,
# the directory left behind, the daemon left running.
suite oddpids.sh <<'EOF'
test_tmpdir
printf '%s\n' "$TEST_TMPDIR" >"$WORK/odddir"
sleep 0 &
track_pid $!
wait $!
notjob=$(sleep 30 >/dev/null 2>&1 & echo $!)
track_pid "$notjob"
printf '%s\n' "$notjob" >"$WORK/oddpid"
test_case() {
  sleep 0 &
  track_pid $!
  wait $!
  assert_eq "in a case" 1 1
}
assert_eq "top" 1 1
run_tests
EOF
run oddpids.sh
expect "an exited or foreign pid does not break the cleanup or the verdict" 0 \
  "ok   top${nl}ok   in a case${nl}${nl}2 passed, 0 failed"
d=$(cat "$WORK/odddir" 2>/dev/null)
p=$(cat "$WORK/oddpid" 2>/dev/null)
if [ -n "$d" ] && [ ! -e "$d" ] && [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then
  pass "and the directory and the foreign process are both gone"
else
  [ -n "$p" ] && kill "$p" 2>/dev/null
  fail "and the directory and the foreign process are both gone" "dir: $d" "pid: $p"
fi

# A directory a case made unwritable, to test a permission failure, is still
# removed -- and under set -e the failing rm once ended the cleanup with exit 1
# after a green summary.
suite rodir.sh <<'EOF'
test_tmpdir
first=$TEST_TMPDIR
mkdir -p "$first/locked/inner"
chmod 500 "$first/locked"
printf '%s\n' "$first" >"$WORK/rodir"
assert_eq "made" 1 1
test_summary
EOF
run rodir.sh
expect "an unwritable directory does not break the verdict" 0 "ok   made${nl}${nl}1 passed, 0 failed"
d=$(cat "$WORK/rodir" 2>/dev/null)
if [ -n "$d" ] && [ ! -e "$d" ]; then
  pass "and is removed"
else
  chmod -R u+rwx "$d" 2>/dev/null
  fail "and is removed" "still there: $d"
fi

# A suite that only borrows a helper, never checking or summarising, leaves no
# tally file behind.
suite helperonly.sh <<'EOF'
next_second 0
printf '%s\n' "$_TL_TALLY" >"$WORK/tallypath"
EOF
run helperonly.sh
t=$(cat "$WORK/tallypath" 2>/dev/null)
if [ -n "$t" ] && [ ! -e "$t" ]; then
  pass "a suite that only uses a helper leaves no file"
else
  fail "a suite that only uses a helper leaves no file" "left: ${t:-no path}"
fi

# Inside a run_tests case they are the case's: gone when it ends, before the
# next case runs.
suite casetmp.sh <<'EOF'
test_makes() {
  test_tmpdir
  printf '%s\n' "$TEST_TMPDIR" >"$WORK/casedir"
  assert_eq "made" 1 1
}
test_next() {
  d=$(cat "$WORK/casedir")
  assert_eq "the previous case made a directory" yes "$([ -n "$d" ] && echo yes || echo no)"
  assert_eq "the previous case's directory is gone" no "$([ -e "$d" ] && echo yes || echo no)"
}
run_tests
EOF
run casetmp.sh
expect "a case's test_tmpdir is removed when the case ends" 0 "*ok   the previous case's directory is gone${nl}*"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
