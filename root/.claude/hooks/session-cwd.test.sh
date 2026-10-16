#!/bin/bash
# Exercises session-cwd.sh, the hook that records where each Claude Code session
# is NOW, for the PR review pipeline (with_current_cwd in bin/pr-review-common.sh).
#
# What it is up against is silent in both directions: a record that is never
# written leaves a moved session unreachable for its own PR, exactly the bug it
# was added for, and a record that is wrong sends a review to a session working
# on something else. So the cases assert the file itself, the one thing the
# reader sees, rather than the hook's exit status -- which is 0 by design
# whatever happens, because a hook must never get in the session's way.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-cwd.sh"
# shellcheck source=bin/test-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../../bin/test-lib.sh" || exit 2

test_tmpdir
DIR="$TEST_TMPDIR/records"

# tmux is stubbed: it records its argv and nothing else. TMUX and TMUX_PANE are
# emptied for every case that does not set them, because this suite is usually
# run from inside tmux and the real hook would otherwise set options on the
# pane running the tests.
#
# Each argument is logged in brackets, so a value split in two by a lost quote
# shows up as two. What tmux then STORES is checked against a real server in
# bin/tmux-conf.test.sh, which runs this hook end to end in the container.
mkdir -p "$TEST_TMPDIR/stub"
cat >"$TEST_TMPDIR/stub/tmux" <<'EOF'
#!/bin/bash
printf '[%s]' "$@" >>"$TMUXLOG"
echo >>"$TMUXLOG"
EOF
chmod +x "$TEST_TMPDIR/stub/tmux"
TMUXLOG="$TEST_TMPDIR/tmux.log"
export TMUXLOG

hook() { # hook <mode> <payload-json>
  printf '%s' "$2" | PATH="$TEST_TMPDIR/stub:$PATH" TMUX="${PANE_TMUX:-}" TMUX_PANE="${PANE_ID:-}" \
    CLAUDE_SESSION_CWD_DIR="$DIR" "$HOOK" "$1"
}
field() { jq -r "$2" "$DIR/$1.json" 2>/dev/null || printf 'absent'; }
count() {
  local n=0 f
  for f in "$DIR"/* "$DIR"/.[!.]*; do [ -e "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

# SessionStart: the session's cwd at start is recorded, so a session that never
# moves has a record that agrees with the registry rather than none at all.
hook start '{"session_id":"s1","hook_event_name":"SessionStart","source":"startup","cwd":"/repo"}'
assert_eq 'start records the session cwd' '/repo' "$(field s1 .cwd)"
assert_status 'with the time it got there, in ms like startedAt' 0 \
  jq -e '.since > 1000000000000' "$DIR/s1.json"

# CwdChanged: new_cwd is the field that names the destination. The common cwd
# field is documented to carry it too, so the two are set apart here to pin
# which one is read.
hook cd '{"session_id":"s1","hook_event_name":"CwdChanged","cwd":"/elsewhere","old_cwd":"/repo","new_cwd":"/repo/git-worktrees/x"}'
assert_eq 'cd records new_cwd' '/repo/git-worktrees/x' "$(field s1 .cwd)"

hook cd '{"session_id":"s2","hook_event_name":"CwdChanged","cwd":"/only-cwd"}'
assert_eq 'without new_cwd, cwd is used' '/only-cwd' "$(field s2 .cwd)"

# `since` is ARRIVAL time, which ranks two sessions in one worktree. SessionStart
# fires again on compaction mid-session, and must not make a session look as
# though it had just arrived where it has been all along.
jq '.since = 5' "$DIR/s1.json" >"$DIR/s1.tmp" && mv "$DIR/s1.tmp" "$DIR/s1.json"
hook start '{"session_id":"s1","source":"compact","cwd":"/repo/git-worktrees/x"}'
assert_eq 'staying put keeps the arrival time' '5' "$(field s1 .since)"
hook cd '{"session_id":"s1","new_cwd":"/repo"}'
assert_status 'moving restamps it' 0 jq -e '.since > 5' "$DIR/s1.json"

# SessionEnd: the record goes with the session.
# The previous record is read only to keep `since`, so one that is unreadable
# must be replaced, not trusted: if jq failed on it, the hook would write
# nothing on every later cd, and the session would stay unreachable for its
# worktree until SessionEnd -- the bug this hook exists to fix, silently back.
for old in 'garbage' '[]' '{"cwd":"/z","since":"x"}'; do
  printf '%s' "$old" >"$DIR/sx.json"
  hook cd '{"session_id":"sx","new_cwd":"/z"}'
  assert_eq "an unreadable previous record ($old) is replaced" '/z number' \
    "$(field sx .cwd) $(field sx '.since | type')"
done
rm -f "$DIR/sx.json"

hook end '{"session_id":"s1","hook_event_name":"SessionEnd","reason":"exit"}'
assert_eq 'end removes the record' 'absent' "$(field s1 .cwd)"
assert_eq 'and only that one' '/only-cwd' "$(field s2 .cwd)"

# The id names a file. One that could leave the directory, or that is missing,
# writes nothing at all rather than something sanitised into a different id.
before=$(count)
hook cd '{"session_id":"../escape","new_cwd":"/x"}'
assert_eq 'an id that is not a plain name writes nothing' "$before" "$(count)"
assert_status 'and nothing outside the directory' 1 test -e "$TEST_TMPDIR/escape.json"
hook cd '{"new_cwd":"/x"}'
assert_eq 'no id writes nothing' "$before" "$(count)"
hook cd 'not json'
assert_eq 'a payload that is not JSON writes nothing' "$before" "$(count)"
# Counted, not just looked up: this path still creates the temp file before jq
# decides there is no record, and only the hook's own cleanup removes it. The
# month-old sweep matches *.json, so a leftover *.json.tmp.* would stay forever.
hook cd '{"session_id":"s3"}'
assert_eq 'a payload naming no directory writes nothing' "$before" "$(count)"

# A hook must never get in the session's way, whatever happened.
assert_status 'a bad payload still exits 0' 0 hook cd 'not json'
assert_status 'an unknown mode exits 0' 0 hook bogus '{"session_id":"s4","cwd":"/x"}'
assert_eq 'and does nothing' 'absent' "$(field s4 .cwd)"
mkdir -p "$TEST_TMPDIR/ro"
chmod 500 "$TEST_TMPDIR/ro"
assert_status 'an unwritable directory still exits 0' 0 \
  env CLAUDE_SESSION_CWD_DIR="$TEST_TMPDIR/ro/records" "$HOOK" cd \
  <<<'{"session_id":"s5","new_cwd":"/x"}'

# A session that crashes fires no SessionEnd, so its record stays. The reader
# never looks at it (records are looked up by live ids only), so the cost is
# only the files: start sweeps any untouched for a month.
hook cd '{"session_id":"old","new_cwd":"/x"}'
touch -t 200001010000 "$DIR/old.json"
hook start '{"session_id":"s6","cwd":"/y"}'
assert_eq 'start sweeps a month-old record' 'absent' "$(field old .cwd)"
assert_eq 'and keeps a current one' '/only-cwd' "$(field s2 .cwd)"

# The same cwd goes onto the session's tmux pane as @claude_cwd, which the
# prefix + p / t bindings read in display-popup's -d: a session that ran `gw`
# should open its popups in the worktree, while #{pane_current_path} is the
# claude process's own directory, which a Bash-tool cd never moves.
assert_eq 'outside tmux, tmux is never called' 'absent' "$(cat "$TMUXLOG" 2>/dev/null || echo absent)"
PANE_TMUX=/tmp/tmux-1/default,1,0 PANE_ID=%7
hook cd '{"session_id":"p1","new_cwd":"/repo/git-worktrees/x"}'
assert_eq 'cd publishes the cwd on its pane' \
  '[set-option][-p][-t][%7][@claude_cwd][/repo/git-worktrees/x]' "$(tail -n 1 "$TMUXLOG")"
hook start '{"session_id":"p1","cwd":"/repo"}'
assert_eq 'start publishes it too' '[set-option][-p][-t][%7][@claude_cwd][/repo]' "$(tail -n 1 "$TMUXLOG")"
hook cd '{"session_id":"p1","new_cwd":"/repo/with space"}'
assert_eq 'a path with a space stays one argument' \
  '[set-option][-p][-t][%7][@claude_cwd][/repo/with space]' "$(tail -n 1 "$TMUXLOG")"
# A trailing ";" on argv is a command separator to tmux; `\;` is its escape.
hook cd '{"session_id":"p1","new_cwd":"/odd;"}'
assert_eq 'a trailing semicolon is escaped' '[set-option][-p][-t][%7][@claude_cwd][/odd\;]' "$(tail -n 1 "$TMUXLOG")"
# Publishing is not skipped when the directory is unchanged: `claude --resume`
# can reopen the same session id in a NEW pane, which has no @claude_cwd yet,
# and SessionStart there carries the same cwd the record already holds.
PANE_ID=%8
hook start '{"session_id":"p1","cwd":"/odd;"}'
assert_eq 'an unchanged cwd is still published, to whichever pane runs it now' \
  '[set-option][-p][-t][%8][@claude_cwd][/odd\;]' "$(tail -n 1 "$TMUXLOG")"
# The option must describe the record that was actually written. A directory
# where the record belongs is the case that bit: `mv` moved the record INTO it,
# returned 0, and the hook then published an empty cwd read from a directory.
mkdir -p "$DIR/p2.json"
lines=$(wc -l <"$TMUXLOG" | tr -d ' ')
before=$(count)
hook cd '{"session_id":"p2","new_cwd":"/never-recorded"}'
assert_eq 'a record that could not be written is not published' "$lines" "$(wc -l <"$TMUXLOG" | tr -d ' ')"
assert_eq 'and nothing is moved into what is in its way' '' "$(ls -A "$DIR/p2.json")"
assert_eq 'nor is its temp file left behind' "$before" "$(count)"
rm -rf "$DIR/p2.json"
PANE_ID=%7
hook end '{"session_id":"p1"}'
assert_eq 'end unsets it, so the popup falls back to the pane path' \
  '[set-option][-p][-u][-t][%7][@claude_cwd]' "$(tail -n 1 "$TMUXLOG")"
lines=$(wc -l <"$TMUXLOG" | tr -d ' ')
before=$(count)
hook cd '{"session_id":"p1"}'
assert_eq 'nothing is published when no record was written' "$lines" "$(wc -l <"$TMUXLOG" | tr -d ' ')"
assert_eq 'and no file is left behind' "$before" "$(count)"
unset PANE_TMUX PANE_ID

test_summary
