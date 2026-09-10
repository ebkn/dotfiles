#!/bin/bash
# Exercises bin/pr-review-common.sh, the single-holder lock both review-pipeline
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

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-review-common.sh"
# shellcheck source=pr-review-common.sh
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

echo
echo "== session_in_worktree =="
# Built against a REAL repository with REAL nested worktrees, laid out the way
# `gw` lays them out (<checkout>/git-worktrees/<name>), because the nesting is
# the entire hazard: the main checkout is a string prefix of every worktree
# under it. A fixture of invented paths would reproduce that, but not the part
# worth pinning -- that `git worktree list` is what decides which of those paths
# is a worktree at all.
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feat-a "$REPO/git-worktrees/a" >/dev/null 2>&1
git -C "$REPO" worktree add -q -b feat-b "$REPO/git-worktrees/b" >/dev/null 2>&1
# Not a worktree, just a directory that sits in the same place one would.
mkdir -p "$REPO/git-worktrees/not-a-worktree"

WTS=$(worktree_paths_json "$REPO")
eq 'worktree_paths_json finds all three' '3' "$(printf '%s' "$WTS" | jq 'length')"
eq 'and only real worktrees' 'false' \
  "$(printf '%s' "$WTS" | jq --arg p "$REPO/git-worktrees/not-a-worktree" 'index($p) != null')"

agents=$(jq -n --arg r "$REPO" '[
  {kind:"interactive", pid:1, sessionId:"main",  startedAt:1, status:"idle", cwd:$r},
  {kind:"interactive", pid:2, sessionId:"in-a",  startedAt:2, status:"idle", cwd:($r + "/git-worktrees/a")},
  {kind:"interactive", pid:3, sessionId:"deep-b",startedAt:3, status:"idle", cwd:($r + "/git-worktrees/b/src/pkg")}
]')

# session_in_worktree prints NOTHING when there is no match, so a jq `// "none"`
# never runs -- jq with no input produces no output. The absent case is half of
# what is under test here, so it needs a name of its own rather than an empty
# string that could equally mean "the helper broke".
sid() { # sid <agents-json> <worktree> <worktrees-json>
  local out
  out=$(session_in_worktree "$1" "$2" "$3")
  if [ -z "$out" ]; then printf 'none'; else printf '%s' "$out" | jq -r '.sessionId'; fi
}
sess() { sid "$agents" "$1" "$WTS"; }

# The regression this exists for. Before the longest-prefix rule the main
# checkout matched all three sessions and, taking the newest, delivered a review
# to whichever session started last -- measured on the real machine as a session
# on an unrelated branch.
eq 'the main checkout claims only its own session' 'main' "$(sess "$REPO")"
eq 'a nested worktree claims its own' 'in-a' "$(sess "$REPO/git-worktrees/a")"
eq 'a cwd deep inside a worktree still belongs to it' 'deep-b' "$(sess "$REPO/git-worktrees/b")"

# A sibling with no session must not fall back to an ancestor's.
git -C "$REPO" worktree add -q -b feat-c "$REPO/git-worktrees/c" >/dev/null 2>&1
eq 'an empty worktree matches nothing' 'none' \
  "$(sid "$agents" "$REPO/git-worktrees/c" "$(worktree_paths_json "$REPO")")"

# Prefix matching must respect path segments: /a must not swallow /ab.
git -C "$REPO" worktree add -q -b feat-ab "$REPO/git-worktrees/ab" >/dev/null 2>&1
agents_ab=$(jq -n --arg r "$REPO" '[
  {kind:"interactive", pid:4, sessionId:"in-ab", startedAt:4, status:"idle", cwd:($r + "/git-worktrees/ab")}
]')
WTS2=$(worktree_paths_json "$REPO")
eq 'worktree a does not claim worktree ab' 'none' \
  "$(sid "$agents_ab" "$REPO/git-worktrees/a" "$WTS2")"
eq 'worktree ab claims its own' 'in-ab' \
  "$(sid "$agents_ab" "$REPO/git-worktrees/ab" "$WTS2")"

echo
echo "== session_in_worktree: several sessions in ONE worktree =="
# Two sessions in one worktree already break the one-writer rule the pipeline
# rests on, so there is no correct answer -- only a documented one. Newest wins,
# and it must be exactly one, never both.
multi=$(jq -n --arg r "$REPO" '[
  {kind:"interactive", pid:5, sessionId:"older", startedAt:10, status:"idle", cwd:($r + "/git-worktrees/a")},
  {kind:"interactive", pid:6, sessionId:"newer", startedAt:20, status:"idle", cwd:($r + "/git-worktrees/a")}
]')
eq 'the newest session wins' 'newer' \
  "$(session_in_worktree "$multi" "$REPO/git-worktrees/a" "$WTS2" | jq -r .sessionId)"
eq 'exactly one is returned' '1' \
  "$(session_in_worktree "$multi" "$REPO/git-worktrees/a" "$WTS2" | jq -s 'length')"

echo
echo "== session_in_worktree: only interactive sessions =="
bg=$(jq -n --arg r "$REPO" '[
  {kind:"background", pid:7, sessionId:"bg", startedAt:99, status:"idle", cwd:($r + "/git-worktrees/a")}
]')
eq 'a background session is not a delivery target' 'none' \
  "$(sid "$bg" "$REPO/git-worktrees/a" "$WTS2")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
