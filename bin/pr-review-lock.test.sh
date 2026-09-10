#!/bin/bash
# Exercises bin/pr-review-lock.sh, the single-holder lock both review-pipeline
# programs take. It is small, but every way it can be wrong is silent and
# one-directional:
#
#   - refusing to steal a dead holder's lock stops the pipeline FOREVER, with no
#     output at all, because both programs exit 0 when they cannot take it;
#   - stealing a live holder's lock lets two runs interleave writes to the same
#     job file, which shows up as a review queued twice or delivered twice.
#
# Liveness is therefore tested against REAL processes -- a backgrounded sleep
# for the live case, and a pid that has been started and reaped for the dead
# one -- rather than against invented numbers, since a pid that happens to be
# reused would make an invented one pass for the wrong reason.
#
# Written for bash 3.2 (/bin/bash on macOS).
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-review-lock.sh"
# shellcheck source=pr-review-lock.sh
. "$LIB"

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  printf '  ok   %s\n' "$1"
}
no() {
  fail=$((fail + 1))
  printf '  FAIL %s\n' "$1"
  [ $# -gt 1 ] && printf '       %s\n' "$2"
}
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "want=[$2] got=[$3]"; fi; }

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap '/bin/rm -rf "$TMP"' EXIT

LOCK="$TMP/lock"

held() { [ -d "$1" ] && echo yes || echo no; }

echo "-- taking a free lock --"
take_lock "$LOCK"
eq 'take_lock succeeds' '0' "$?"
eq 'the directory exists' 'yes' "$(held "$LOCK")"
eq 'the holder pid is recorded' "$$" "$(cat "$LOCK/pid")"

echo "-- a lock held by a LIVE process is not stolen --"
sleep 30 &
live=$!
printf '%s' "$live" >"$LOCK/pid"
take_lock "$LOCK"
eq 'take_lock refuses' '1' "$?"
eq 'the live holder still owns it' "$live" "$(cat "$LOCK/pid")"

echo "-- a run that did not take the lock must not release it --"
release_lock "$LOCK"
eq 'the lock survives' 'yes' "$(held "$LOCK")"
eq 'and still names its holder' "$live" "$(cat "$LOCK/pid")"
kill "$live" 2>/dev/null
wait "$live" 2>/dev/null

echo "-- a lock held by a DEAD process is stolen --"
# Started and reaped, so this pid is genuinely gone rather than merely unlikely.
sleep 0 &
dead=$!
wait "$dead" 2>/dev/null
printf '%s' "$dead" >"$LOCK/pid"
take_lock "$LOCK"
eq 'take_lock steals it' '0' "$?"
eq 'and records the new holder' "$$" "$(cat "$LOCK/pid")"

echo "-- releasing as the holder --"
release_lock "$LOCK"
eq 'the lock is gone' 'no' "$(held "$LOCK")"

echo "-- release_lock is safe when there is no lock at all --"
release_lock "$LOCK"
eq 'exits 0' '0' "$?"

echo "-- a lock with an unreadable pid falls back to age, not to always-steal --"
# mkdir can succeed while the pid write fails (a full or read-only volume), and
# a lock written by an older version has no pid file either. Such a lock must
# still be respected while it is plausibly live -- otherwise the fallback would
# be indistinguishable from having no lock.
mkdir "$LOCK"
take_lock "$LOCK"
eq 'a fresh pidless lock is respected' '1' "$?"

touch -t 200001010000 "$LOCK"
take_lock "$LOCK"
eq 'an ancient pidless lock is stolen' '0' "$?"
eq 'the stealer records itself' "$$" "$(cat "$LOCK/pid")"
release_lock "$LOCK"

echo "-- a garbage pid is treated as unreadable, not as a live holder --"
mkdir "$LOCK"
printf 'not-a-pid' >"$LOCK/pid"
take_lock "$LOCK"
eq 'respected while fresh' '1' "$?"
touch -t 200001010000 "$LOCK"
take_lock "$LOCK"
eq 'stolen once ancient' '0' "$?"
release_lock "$LOCK"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
