#!/bin/bash
#
# tmux-track-session.test.sh
#
# Two suites, one per silent failure of this script.
#
# (1) The two-way exclusivity of the conn_id <-> session binding: one conn_id
# names one session, and one session is named by at most one conn_id. Losing
# either direction is silent -- the symptom is two WezTerm tabs mirroring the
# same remote session some minutes later, after an autossh reconnect, with
# nothing at the moment of the switch to suggest what happened.
#
# (2) The monitor must die quietly. It runs as a `run-shell -b` job, and tmux
# reports such a job dying by a signal as "'<cmd>' terminated by signal 15" in a
# view mode covering the pane -- which here is the *remote* screen of an ssh
# session. `attach` TERMs the previous connection's monitor on every reconnect,
# so it fired every time the link came back. That suite has a harness of its own
# (see its comment below) and lives at the bottom of this file.
#
# Runs against a real throwaway tmux server with real attached clients, not a
# stubbed tmux: the decisions here are readings of `session_attached` and
# `list-sessions -f`, so a stub would keep passing if tmux changed what those
# mean. Isolation is TMUX_TMPDIR rather than -L, because the script under test
# calls bare `tmux` -- with -L the calls would land on the developer's own
# server, and `attach` ends in `new-session -A`, which would create a session
# there. TMUX must be unset for the same reason a client can exist at all: tmux
# refuses a nested attach.
#
# Clients are real ptys via script(1). Everything the script does depends on a
# client existing (the monitor polls one, attach becomes one), so there is no
# useful version of this test without them.

set -u
# A tmux suite: container or CI only (see bin/tmux-test-guard.sh).
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2

DIR=$(mktemp -d)
export TMUX_TMPDIR="$DIR/tmux"
export XDG_STATE_HOME="$DIR/state"
# The monitor's poll interval, down from 2s. Every switch and every death below
# is noticed only at the monitor's next poll, so this is most of the suite's
# waiting. Exported before any server starts: `attach` launches its monitor
# through run-shell, which runs with the server's environment, not ours.
export TMUX_TRACK_SESSION_POLL=0.05
unset TMUX TMUX_PANE
mkdir -p "$TMUX_TMPDIR"
SESSION_DIR="$XDG_STATE_HOME/tmux-track-session/session"
PID_DIR="$XDG_STATE_HOME/tmux-track-session/pid"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/tmux-track-session"
IDLE='sleep 600'
CLIENT_PIDS=""
MONITOR_PIDS=""
INNER="track-inner-$$"
OUTER="track-outer-$$"
fails=0

command -v tmux >/dev/null || {
  echo "tmux is required" >&2
  exit 1
}

# Every monitor this run started, by pid. Monitors started by hand contribute
# their $!; monitors started by `attach` write their own pid into PID_DIR, which
# is inside this run's XDG_STATE_HOME and so cannot name anybody else's.
#
# This used to be `pkill -f "tmux-track-session monitor"`, which matches on the
# whole machine: a monitor belonging to a live ssh connection into this host, or
# to a second copy of this suite running beside it, was killed along with ours.
# Verified by leaving a process with that argv shape running across a full run
# and finding it gone afterwards.
kill_our_monitors() {
  local p f
  for p in $MONITOR_PIDS; do kill "$p" 2>/dev/null; done
  for f in "$PID_DIR"/*; do
    [ -f "$f" ] || continue
    kill "$(cat "$f")" 2>/dev/null
  done
}

cleanup() {
  for p in $CLIENT_PIDS; do kill "$p" 2>/dev/null; done
  kill_our_monitors
  tmux kill-server 2>/dev/null
  tmux -L "$INNER" kill-server 2>/dev/null
  tmux -L "$OUTER" kill-server 2>/dev/null
  TMUX_TMPDIR="$DIR/adopt-tmux" tmux kill-server 2>/dev/null
  rm -rf "$DIR"
}
trap cleanup EXIT

t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

record() {
  mkdir -p "$SESSION_DIR"
  printf '%s' "$2" >"$SESSION_DIR/$1"
}
read_record() { cat "$SESSION_DIR/$1" 2>/dev/null || echo '<none>'; }
# Poll for a record to reach <expected> rather than sleeping a fixed amount and
# reading once. Returns as soon as it matches, so a pass is immediate and only a
# genuine failure pays the timeout -- and the value it echoes on timeout is the
# real one, so the failure report names what was actually there. The 6s ceiling
# (and wait_gone's 5s) still covers the monitor's default 2s poll, which a
# signal or a switch has to wait out, so a run with TMUX_TRACK_SESSION_POLL
# unset is slow rather than red.
wait_record() { # wait_record <conn_id> <expected>
  for _ in $(seq 1 60); do
    [ "$(read_record "$1")" = "$2" ] && break
    sleep 0.1
  done
  read_record "$1"
}
# Used by both suites, so it lives up here with the other shared helpers.
wait_gone() { # wait_gone <pid>
  for _ in $(seq 1 50); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}
# Poll for a monitor to reach its loop, which it announces by writing its pid.
#
# Reported as a FAIL rather than exiting, for the reason attach_as does the
# same: this aborted the whole run, so a monitor that never started printed one
# line of stderr and *no assertion results at all* -- not one ok, not one FAIL,
# no count. Verified by stopping the monitor from writing its pid file: the
# entire output was "monitor for connA never started". A red CI job that says
# nothing about which contract broke is barely better than a green one.
wait_running() { # wait_running <conn_id>
  for _ in $(seq 1 100); do
    [ -s "$PID_DIR/$1" ] && return 0
    sleep 0.1
  done
  printf 'FAIL monitor for %s never started within 10s\n' "$1"
  fails=$((fails + 1))
  return 1
}

# script(1) is the only way to hand tmux a pty, and its command-line differs
# between BSD (macOS: `script -q <file> <cmd...>`) and util-linux (CI:
# `script -qec "<cmd>" <file>`). Probe rather than branch on the platform --
# macOS also ships util-linux via Homebrew.
#
# TERM is supplied, and unconditionally. A GitHub runner provides none, and tmux
# then refuses the pty outright -- "open terminal failed: terminal does not
# support clear" -- which reaches this test only as `timed out attaching a client`
# after the wait loop, so it reads as a tracking bug rather than a missing
# variable. Reproduced in an ubuntu:24.04 container: identical failure with TERM
# unset, green with it set. The value is not a property of the developer's
# terminal, because the client being attached is tmux's own and not theirs.
if script -q /dev/null echo probe 2>/dev/null | grep -q probe; then
  in_pty() { env TERM=xterm-256color script -q /dev/null "$@" >/dev/null 2>&1 & }
else
  in_pty() { env TERM=xterm-256color script -qec "$*" /dev/null >/dev/null 2>&1 & }
fi

# Attach a real client to <session> and return once tmux reports it.
new_client() {
  in_pty tmux attach -t "=$1"
  CLIENT_PIDS="$CLIENT_PIDS $!"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ "$(tmux list-clients -f "#{==:#{client_session},$1}" -F x 2>/dev/null | wc -l)" -gt 0 ] && return 0
    sleep 0.2
  done
  echo "timed out attaching a client to $1" >&2
  return 1
}

tty_on() { tmux list-clients -f "#{==:#{client_session},$1}" -F '#{client_tty}' | head -1; }
# How many clients the server holds. `attach` ends by becoming one, so a rise
# here is the one signal that says it got all the way through.
client_count() { tmux list-clients -F x 2>/dev/null | wc -l | tr -d ' '; }

tmux -f /dev/null new-session -d -s s1 "$IDLE"
# Sessions that `attach` creates itself get their pane from default-command. It
# must not be the developer's shell: zsh here sources .zshrc, whose own tmux
# auto-start and hooks fight the test (the same trap tmux-pane-titles.test.sh
# documents), and the pane exits before anything can be asserted about it.
tmux set -g default-command "$IDLE"
tmux new-session -d -s s2 "$IDLE"
tmux new-session -d -s free "$IDLE"

# ---------------------------------------------------------------------------
# monitor: claiming a session releases it from every other conn_id.
# This is the regression. connA owns s1; the user switches connB's client onto
# s1 with prefix + w. Without the release, both records name s1 and the next
# reconnect puts two clients on it.
# ---------------------------------------------------------------------------
new_client s1 || exit 1
new_client s2 || exit 1
ttyA=$(tty_on s1)
ttyB=$(tty_on s2)
"$SCRIPT" monitor connA "$ttyA" >/dev/null 2>&1 &
MONITOR_PIDS="$MONITOR_PIDS $!"
"$SCRIPT" monitor connB "$ttyB" >/dev/null 2>&1 &
MONITOR_PIDS="$MONITOR_PIDS $!"

# Both monitors have to have made their FIRST claim before anything is switched.
# The records are not pre-seeded and the pid file is not the signal: a monitor
# writes its pid before its first claim, so a switch landing in between let
# connA's first claim come after connB's, take s1 back and release connB -- a
# stable wrong state, failing the case below on timing alone.
t "monitor: connA claims its starting session" "s1" "$(wait_record connA s1)"
t "monitor: connB claims its starting session" "s2" "$(wait_record connB s2)"

tmux switch-client -c "$ttyB" -t '=s1'

# Poll rather than sleeping out two poll intervals. The second suite in this
# file already established why: a fixed read made its regression case pass green
# against the unfixed script, and the same hazard applies here -- the monitor is
# inside its poll `sleep` when the switch lands, so how long this takes is not
# bounded by anything the test controls. wait_record returns the moment it
# matches and reports the real value if it never does.
t "monitor: the claimant records the session" "s1" "$(wait_record connB s1)"
t "monitor: the previous owner is released" "<none>" "$(wait_record connA '<none>')"

dupes=$(for f in "$SESSION_DIR"/*; do [ -f "$f" ] && {
  cat "$f"
  echo
}; done | sort | uniq -d)
t "monitor: no two conn_ids name the same session" "" "$dupes"

kill_our_monitors
for p in $MONITOR_PIDS; do wait_gone "$p"; done
MONITOR_PIDS=""

# ---------------------------------------------------------------------------
# monitor: when it stops. It must end with its client, or every connection
# leaves one polling forever -- and remove its pid file on the way, or the next
# attach signals a pid the OS may have handed to someone else.
# ---------------------------------------------------------------------------
tmux new-session -d -s s3 "$IDLE"
new_client s3 || exit 1
ttyK=$(tty_on s3)
"$SCRIPT" monitor connK "$ttyK" >/dev/null 2>&1 &
monitor_k=$!
MONITOR_PIDS="$MONITOR_PIDS $monitor_k"
wait_record connK s3 >/dev/null
tmux detach-client -t "$ttyK"
t "monitor: ends once its client is gone" "gone" \
  "$(wait_gone "$monitor_k" && echo gone || echo still-running)"
t "monitor: and removes its pid file" "absent" \
  "$([ -e "$PID_DIR/connK" ] && echo present || echo absent)"

# run-shell is what expands #{client_tty}; if it ever reaches the monitor
# unexpanded there is no client to watch, and the monitor must not start a loop
# against the literal string.
"$SCRIPT" monitor connL '#{client_tty}' >/dev/null 2>&1 &
monitor_l=$!
t "monitor: an unexpanded client_tty exits at once" "gone" \
  "$(wait_gone "$monitor_l" && echo gone || echo still-running)"
t "monitor: and starts nothing" "absent" \
  "$([ -e "$PID_DIR/connL" ] && echo present || echo absent)"

# ---------------------------------------------------------------------------
# attach: resolution. It ends in `exec tmux new-session -A`, which attaches, so
# it is run under a pty like any other client and the assertions are on where it
# landed.
# ---------------------------------------------------------------------------
# Run `attach` under a pty and return once tmux reports the client it became.
#
# Waiting for that client rather than sleeping a fixed three seconds, because
# the assertions below otherwise read whatever the server happened to hold when
# the timer expired -- and one of them passes in that state without `attach`
# having done anything at all. "does not join a session another client holds"
# expects `held 1`, which is exactly what `new_client held` already left there:
# stopping the script just before it attaches leaves that assertion green.
# Slowing `attach` to six seconds showed the other half of the same problem, a
# late attach from one case being counted by the next case's wait.
#
# A timeout here is a failure of the script, not of the harness, so it is
# reported as one instead of aborting -- the cases after it still say something.
attach_as() { # attach_as <conn_id>
  local before
  before=$(client_count)
  in_pty "$SCRIPT" attach "$1"
  CLIENT_PIDS="$CLIENT_PIDS $!"
  for _ in $(seq 1 100); do
    [ "$(client_count)" -gt "$before" ] && return 0
    sleep 0.1
  done
  printf 'FAIL attach as %s never became a client within 10s\n' "$1"
  fails=$((fails + 1))
  return 1
}

# A free recorded session is restored.
record connC free
attach_as connC
t "attach: restores a recorded session that is free" "1" \
  "$(tmux list-sessions -F '#{session_name} #{session_attached}' | grep -c '^free 1$')"

# A recorded session that another client holds is NOT joined: joining it would
# mirror that tab. The connection falls back to its own conn_id session.
# A session of its own, so the client count is unambiguous: the block above
# deliberately leaves two clients on s1.
tmux new-session -d -s held "$IDLE"
new_client held || exit 1
record connD held
# The only assertion here whose expected value is also the state *before*
# `attach` runs: `held` already has the one client new_client gave it, so
# "still 1" is what a script that did nothing leaves behind. Its precondition is
# therefore made explicit rather than assumed -- every other case in this file
# expects a value that only appears once attach has done its work, and so goes
# red on its own.
if attach_as connD; then
  t "attach: does not join a session another client holds" "1" \
    "$(tmux list-sessions -F '#{session_name} #{session_attached}' | grep -c '^held 1$')"
  t "attach: falls back to its own conn_id session" "1" \
    "$(tmux list-sessions -F '#{session_name} #{session_attached}' | grep -c '^connD 1$')"
fi

# A record naming a session that no longer exists is pruned rather than kept --
# and only that one. connF names a session that exists (held, with its client),
# so it must survive the prune even though nothing follows it.
record connE gone-session
record connF held
attach_as connE2
t "attach: prunes a record naming a dead session" "<none>" "$(read_record connE)"
t "attach: keeps another conn_id's record of a live session" "held" "$(read_record connF)"

# The prefix boundary the script's two listings are newline-delimited for:
# `local-5` must not be found inside `local-50`. local-50 is live and free;
# local-5 does not exist, so connX's record of it is dead.
tmux new-session -d -s local-50 "$IDLE"
record connX local-5
attach_as connX
t "attach: a dead session is not matched inside a longer live name" \
  "connX" "$(wait_record connX connX)"
t "attach: and the connection gets its own session, not the longer one" "0" \
  "$(tmux list-sessions -F '#{session_name} #{session_attached}' | grep -c '^local-50 1$')"

# The case above goes red only if BOTH checks lose their boundary: local-5 is
# dead, so the prune drops the record before the free check ever reads it.
# Here local-5 is live and held, so the record survives the prune and only the
# free check stands between it and a join. Matched without its boundary,
# local-5 is "found" among the free sessions inside local-50, and the
# connection joins a session another client holds: two tabs, one session.
tmux new-session -d -s local-5 "$IDLE"
# The longer free name is this case's own, not the local-50 the case above
# left behind: without one, an unbounded match has nothing to match wrongly and
# the case passes whatever the boundary does.
tmux new-session -d -s local-51 "$IDLE"
t "setup: local-51 is free" "1" \
  "$(tmux list-sessions -f '#{==:#{session_attached},0}' -F '#{session_name}' | grep -cx local-51)"
if new_client local-5; then
  record connY local-5
  if attach_as connY; then
    t "attach: a held session is not taken for free inside a longer free name" "1" \
      "$(tmux list-sessions -F '#{session_name} #{session_attached}' | grep -c '^local-5 1$')"
    t "attach: so the connection gets its own session" "1" \
      "$(tmux list-sessions -F '#{session_name} #{session_attached}' | grep -c '^connY 1$')"
  fi
else
  t "setup: a client on local-5" "attached" "timed out"
fi

# And the prune's own boundary, which the dead-local-5 case above cannot pin on
# its own: there the free check discards connX's record anyway. Here the dead
# record belongs to ANOTHER conn_id, which only the prune ever looks at. local-7
# does not exist, local-70 does; matched without its boundary the record is
# "found" inside local-70 and kept, and a later connection reusing connZ's id
# would be handed a session name that means nothing.
tmux new-session -d -s local-70 "$IDLE"
record connZ local-7
attach_as connZ2
t "attach: prunes another conn_id's dead record even inside a longer live name" \
  "<none>" "$(read_record connZ)"

# attach must also START the monitor, which is the half that keeps the record
# up to date for the next reconnect. Nothing above reaches it: every case here
# asserts only where attach landed, and the monitor suite below starts a monitor
# by hand. So the one line that connects the two -- the `run-shell -b` in
# attach -- had no coverage at all, and it invokes the script through a path
# outside this checkout. With no seam that path is $HOME/.local/bin, which does
# not exist on a CI runner (relink is never run there) and points at the *main*
# checkout rather than the worktree under test on a developer machine: the
# monitor then silently never starts, or starts from the wrong copy, and every
# assertion still passes.
#
# A conn_id with no record of its own, so the session attach creates is named
# after it and the value the monitor is expected to write is known in advance.
attach_as connG
t "attach: starts the monitor, which records the session" "connG" \
  "$(wait_record connG connG)"

# attach kills the previous connection's monitor on every reconnect, reading the
# pid out of a file. A monitor that died without running its trap -- SIGKILL, or
# the machine losing the process -- leaves that file behind, and the OS is then
# free to hand the number to something else entirely. Signalling it blind kills
# a bystander, on the remote, with nothing said anywhere.
#
# This is the opposite direction from bin/pr-review-common.sh, where `kill -0` is
# enough: there a recycled pid costs a missed steal, here it costs somebody
# else's process, so the pid has to be identified and not merely found alive.
sleep 600 &
bystander=$!
CLIENT_PIDS="$CLIENT_PIDS $bystander"
mkdir -p "$XDG_STATE_HOME/tmux-track-session/pid"
printf '%s' "$bystander" >"$XDG_STATE_HOME/tmux-track-session/pid/connH"
attach_as connH
t "attach: leaves an unrelated process holding a recycled pid alone" "alive" \
  "$(kill -0 "$bystander" 2>/dev/null && echo alive || echo dead)"

# The other half of the same decision: a pid that really is this conn_id's
# monitor must still be killed, or every reconnect leaks one.
#
# ...and the pid file then names the NEW monitor attach started. The old one's
# trap runs only once its poll `sleep` returns -- in production usually after
# attach has started the new monitor -- and it used to remove the pid file
# unconditionally, taking the new monitor's with it. The next reconnect then had
# nothing to kill, and leaked it.
#
# That order is the case's precondition, so the test imposes it instead of
# leaving it to the poll interval: the old monitor is stopped (SIGSTOP) while
# attach runs, so attach's TERM stays pending, and it is continued only once the
# replacement has written its pid. Left to timing, the case passed against the
# unconditional removal whenever attach outlasted the old monitor's poll -- under
# parallel load in the container, even at a 2s poll.
"$SCRIPT" monitor connI "$ttyA" >/dev/null 2>&1 &
monitor_i=$!
CLIENT_PIDS="$CLIENT_PIDS $monitor_i"
for _ in $(seq 1 50); do
  [ -s "$PID_DIR/connI" ] && break
  sleep 0.1
done
# yes when the pid file names a connI monitor other than the old one.
names_replacement() {
  new_pid=$(cat "$PID_DIR/connI" 2>/dev/null)
  if [ "${new_pid:-0}" = "$monitor_i" ]; then
    echo "no (pid file: still the old monitor)"
    return
  fi
  case "$(ps -ww -p "${new_pid:-0}" -o command= 2>/dev/null)" in
    *"monitor connI "*) echo yes ;;
    *) echo "no (pid file: ${new_pid:-missing})" ;;
  esac
}
kill -STOP "$monitor_i"
# It watches $ttyA's client; with that gone it would have exited on its own, and
# every case below would pass without attach having signalled anything.
t "attach harness: the old monitor is alive and held when attach runs" "alive" \
  "$(kill -0 "$monitor_i" 2>/dev/null && echo alive || echo dead)"
attach_as connI
for _ in $(seq 1 50); do
  [ "$(names_replacement)" = yes ] && break
  sleep 0.1
done
replaced=$(names_replacement)
kill -CONT "$monitor_i"
gone=dead
for _ in $(seq 1 50); do
  kill -0 "$monitor_i" 2>/dev/null || break
  sleep 0.1
done
kill -0 "$monitor_i" 2>/dev/null && gone=alive
t "attach: still kills this conn_id's own stale monitor" "dead" "$gone"
# HOW it ended is the half the screen suite cannot see, since that one signals
# its monitor itself: attach must send a signal the trap can catch, and the
# monitor must then exit 0, which is what keeps tmux from reporting it over the
# remote screen. A `kill -9` in attach (137) passed the whole suite without
# this; a lost trap (143) and a trap ending in a bare `exit` (1, release_pid's
# status) show here as well. Waited on only once dead: on a live monitor `wait`
# would block for good.
if [ "$gone" = dead ]; then
  wait "$monitor_i"
  t "attach: the monitor it replaces exits 0, so tmux reports nothing" "0" "$?"
fi
if [ "$replaced" = yes ]; then
  t "attach: the pid file names the replacement monitor afterwards" "yes" \
    "$(names_replacement)"
else
  t "attach harness: the replacement monitor starts while the old one is held" \
    "yes" "$replaced"
fi

# The identity check matches this conn_id as a whole argument. A process that is
# the monitor of a LONGER conn_id (local-50's, holding a pid local-5's file
# names) is somebody else's monitor, and killing it breaks that connection.
# (`; exit 0` stops bash exec'ing sleep in its place, which would drop the argv.)
bash -c 'sleep 600; exit 0' tmux-track-session monitor local-50 /dev/null &
other_monitor=$!
CLIENT_PIDS="$CLIENT_PIDS $other_monitor"
printf '%s' "$other_monitor" >"$PID_DIR/local-5"
attach_as local-5
t "attach: a longer conn_id's monitor is not taken for this one's" "alive" \
  "$(kill -0 "$other_monitor" 2>/dev/null && echo alive || echo dead)"

# Every monitor attach started above would otherwise poll at the suite's short
# interval until cleanup -- ten of them, load on every suite running beside this.
kill_our_monitors

# ---------------------------------------------------------------------------
# adopt: the remote half of bin/tmux-restore-ssh-tabs. Each session it prints
# becomes one restored tab connecting with conn_id = that session's name, so
# after it runs every printed session must be recorded under its own name and
# under no other conn_id. A record left crossing (conn a -> session b) sends
# tab "a" into b and tab "b" into b as well: two tabs mirroring one session and
# session a never shown -- the same silent symptom as suite (1).
#
# A server and state dir of its own: the cases above leave clients and records
# scattered over the shared one, and which sessions are free is the input here.
# ---------------------------------------------------------------------------
ADOPT_TMP="$DIR/adopt-tmux"
ADOPT_STATE="$DIR/adopt-state"
ADOPT_SESSIONS="$ADOPT_STATE/tmux-track-session/session"
mkdir -p "$ADOPT_TMP" "$ADOPT_SESSIONS"
at() { TMUX_TMPDIR="$ADOPT_TMP" tmux "$@"; }
arecord() { printf '%s' "$2" >"$ADOPT_SESSIONS/$1"; }
aread() { cat "$ADOPT_SESSIONS/$1" 2>/dev/null || echo '<none>'; }

# Created a second apart and in reverse alphabetical order, so the output order
# can only come from session_created: tmux itself lists by name. Tab order is
# the point -- restored tabs should come back in the order they were opened.
# session_created is in whole seconds, so the wait is for the clock to pass
# zeta's second rather than a full second of sleep: half of one, on average.
# The same helper as tmux-restore-tabs.test.sh's (until bin/test-lib.sh holds
# one): a failed read falls back to the full second, and the wait is bounded.
next_second() { # next_second <session>, on the adopt server
  local created i=0
  created=$(at display-message -p -t "=$1:" '#{session_created}')
  case "$created" in
    '' | *[!0-9]*)
      sleep 1
      return
      ;;
  esac
  while [ "$(date +%s)" -le "$created" ] && [ $((i += 1)) -le 40 ]; do sleep 0.05; done
}
at -f /dev/null new-session -d -s zeta "$IDLE"
next_second zeta
at new-session -d -s alpha "$IDLE"
at new-session -d -s _popup_1 "$IDLE"
at new-session -d -s 'with/slash' "$IDLE"
at new-session -d -s held "$IDLE"
in_pty env TMUX_TMPDIR="$ADOPT_TMP" tmux attach -t =held
CLIENT_PIDS="$CLIENT_PIDS $!"
for _ in $(seq 1 50); do
  [ "$(at list-clients -F x 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && break
  sleep 0.1
done

arecord zeta alpha # crossed: conn zeta was last in alpha
arecord other zeta # a third conn_id naming a session being adopted
arecord live held  # a live connection's record, not ours to touch

# Without its client, `held` is free and the cases below fail as though adopt
# were wrong; say which it is.
t "adopt harness: held has a client" "1" "$(at display-message -p -t '=held:' '#{session_attached}')"

adopted=$(TMUX_TMPDIR="$ADOPT_TMP" XDG_STATE_HOME="$ADOPT_STATE" "$SCRIPT" adopt)
adopt_status=$?
# tmux-restore-ssh-tabs treats a non-zero exit as "adopt failed" and opens
# nothing, so success must say 0 -- a trailing `[ … ] && …` would not.
t "adopt: exits 0" "0" "$adopt_status"
t "adopt: prints the free sessions, oldest first" "zeta alpha" "$(printf '%s' "$adopted" | tr '\n' ' ')"
t "adopt: records each adopted session under its own name (zeta)" "zeta" "$(aread zeta)"
t "adopt: records each adopted session under its own name (alpha)" "alpha" "$(aread alpha)"
t "adopt: releases an adopted session from every other conn_id" "<none>" "$(aread other)"
t "adopt: leaves the record of an attached session alone" "held" "$(aread live)"
at kill-server 2>/dev/null

# No server at all (a remote after a reboot) is "nothing to restore", not a
# failure: the caller would otherwise blame an outdated checkout.
adopted=$(TMUX_TMPDIR="$ADOPT_TMP" XDG_STATE_HOME="$ADOPT_STATE" "$SCRIPT" adopt)
adopt_status=$?
t "adopt: with no server, prints nothing and exits 0" "0:" "$adopt_status:$adopted"

# ---------------------------------------------------------------------------
# The monitor must die quietly.
#
# Two tmux servers, not one, and that is the whole harness: tmux hands a
# run-shell job's output to a *client*, so with nothing attached the message is
# never rendered and every assertion below passes vacuously. The outer server
# exists only to supply the pty the inner one is attached through, and the
# assertions read the inner screen by capturing the outer pane. Both are on
# sockets of their own so the sessions above cannot be mistaken for them.
# ---------------------------------------------------------------------------
pass_() { printf 'ok   %s\n' "$1"; }
fail_() {
  printf 'FAIL %s\n' "$1"
  shift
  for l in "$@"; do printf '       %s\n' "$l"; done
  fails=$((fails + 1))
}

tmux -L "$INNER" -f /dev/null new-session -d -s main -x 80 -y 24 "$IDLE"
tmux -L "$OUTER" -f /dev/null new-session -d -x 80 -y 24 "tmux -L $INNER attach -t main"

# Wait for the inner client to exist, otherwise the job has no one to report to.
client_tty=""
for _ in $(seq 1 50); do
  client_tty=$(tmux -L "$INNER" list-clients -F '#{client_tty}' 2>/dev/null | head -1)
  [ -n "$client_tty" ] && break
  sleep 0.1
done
[ -n "$client_tty" ] || {
  echo "inner client never attached" >&2
  exit 1
}

# The inner screen as the outer pane drew it. A report naming the job's long
# absolute path is drawn wrapped onto two rows, which -J does not rejoin here,
# and the view's position indicator overwrites the end of the first row -- so
# match on short fragments, never on the job's command line.
screen() { tmux -L "$OUTER" capture-pane -pJ; }
clear_screen() { tmux -L "$INNER" send-keys -X cancel 2>/dev/null; }
in_mode() { tmux -L "$INNER" display-message -p -t main '#{pane_in_mode}'; }
# wait_mode 0|1 -- poll until the pane leaves or enters a mode, rather than
# sleeping a fixed amount and reading once. The delay between a job dying and
# its report reaching the screen is not bounded by anything this test controls
# (the job exits, then the inner server renders, then the outer one does): a
# half-second read once made the regression case pass against the unfixed
# script.
wait_mode() {
  for _ in $(seq 1 40); do
    [ "$(in_mode)" = "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

# The harness itself: a signalled job DOES reach the screen. Without this case a
# broken reproduction (nothing attached, wrong socket, a capture that reads the
# wrong pane) would make the real assertion below pass while proving nothing.
#
# `exec`, and it is load-bearing. run-shell runs the job as `sh -c <cmd>`, and
# whether that shell stays in the picture is a property of the platform's sh:
# macOS execs a lone simple command away, dash on Linux forks, leaving *two*
# processes matching the pattern. Picking one of them with `head -1` took the
# wrapper, and killing that reported nothing at all -- the orphaned sleep still
# held the job's output open, so tmux never saw the job end. `exec` collapses
# both platforms to the one process tmux is actually waiting on, which is also
# what the real monitor is: its pid file records the pid of the job's own child.
#
# The job is a private symlink to `sleep` under $DIR, named after this run, and
# the pattern is that name, not a distinctive duration. `pgrep -f` reads the
# whole machine's process table, which is the same trap kill_our_monitors above
# was written to escape: a second copy of this suite, or any unrelated process
# whose argv happens to match, is otherwise indistinguishable from our own job.
# A name carrying $$ cannot name anything outside this run.
sanity_cmd="$DIR/sanity-sleep-$$"
ln -s "$(command -v sleep)" "$sanity_cmd"
tmux -L "$INNER" run-shell -b "exec '$sanity_cmd' 3117"
sanity_pid=""
for _ in $(seq 1 50); do
  sanity_pid=$(pgrep -f "sanity-sleep-$$")
  [ -n "$sanity_pid" ] && break
  sleep 0.1
done
# shellcheck disable=SC2086 # deliberately split: the count is the assertion
set -- $sanity_pid
if [ "$#" -eq 0 ]; then
  fail_ "harness: a signalled run-shell job is visible on the client" "the sanity job never started"
elif [ "$#" -gt 1 ]; then
  # Not narrowed to one: more than one match means the pattern no longer names
  # the job's own child, and picking one of them silently is exactly how this
  # case came to assert nothing on Linux. Killed before failing, because a job
  # outlives the server -- measured: still running after `kill-server`, so
  # cleanup() cannot reach it and a failed run would leak it for its full hour.
  kill -TERM "$@" 2>/dev/null
  fail_ "harness: a signalled run-shell job is visible on the client" \
    "the sanity job matched more than one process: $*"
else
  kill -TERM "$sanity_pid" 2>/dev/null
  wait_gone "$sanity_pid"
  wait_mode 1
  if screen | grep -q 'terminated by signal'; then
    pass_ "harness: a signalled run-shell job is visible on the client"
  else
    fail_ "harness: a signalled run-shell job is visible on the client" \
      "expected 'terminated by signal' on the inner screen; the harness cannot see the bug it tests for"
  fi
  # The screen case below judges by which report comes FIRST in the view, so
  # it relies on tmux appending a later report under an earlier one rather than
  # starting a new view or putting it on top. Pinned here, where an earlier
  # report is known to be on the screen: a tmux that changed this would leave
  # the sentinel always first, and that case green against a broken monitor.
  tmux -L "$INNER" run-shell -b 'exit 4'
  for _ in $(seq 1 40); do
    screen | grep -q "exit 4' returned 4" && break
    sleep 0.1
  done
  out=$(screen)
  case "$out" in
    *"exit 4' returned 4"*)
      case "${out%%$'\n'*}" in
        *"exit 4' returned 4"*) fail_ "harness: a later job's report is appended below an earlier one" \
          "the later report came first:" "$out" ;;
        *) pass_ "harness: a later job's report is appended below an earlier one" ;;
      esac
      ;;
    *) fail_ "harness: a later job's report is appended below an earlier one" \
      "the later report never appeared:" "$out" ;;
  esac
  clear_screen
fi

# start_inner_monitor <conn_id> -- start a monitor the way `attach` does, as a
# run-shell job on the inner server, and echo its pid once it has written it.
start_inner_monitor() {
  local file="$XDG_STATE_HOME/tmux-track-session/pid/$1" pid=""
  tmux -L "$INNER" run-shell -b "'$SCRIPT' monitor '$1' '$client_tty'"
  for _ in $(seq 1 50); do
    [ -s "$file" ] && pid=$(cat "$file")
    [ -n "$pid" ] && break
    sleep 0.1
  done
  printf '%s' "$pid"
}

conn_id="local-1"
pid_file="$XDG_STATE_HOME/tmux-track-session/pid/$conn_id"
monitor_pid=$(start_inner_monitor "$conn_id")

# A clean screen first: the sanity case's view must be gone, or the first-line
# check below reads its report and fails for a reason that is not the monitor's.
clear_screen
if ! wait_mode 0; then
  fail_ "harness: the inner pane is out of view mode before the monitor is killed" \
    "$(screen)"
elif [ -z "$monitor_pid" ]; then
  fail_ "monitor: starts and records its pid" "no pid in $pid_file"
else
  pass_ "monitor: starts and records its pid"

  # What `attach` does to the previous connection's monitor, in its order: the
  # pid file is removed, then the monitor is signalled. So the trap's
  # release_pid finds no file of its own and returns non-zero, and only the
  # trap's `exit 0` stands between that status and a report. Signalled with its
  # pid file still in place, the case exercised the other branch, and a trap
  # ending in a bare `exit` passed.
  rm -f "$pid_file"
  kill -TERM "$monitor_pid" 2>/dev/null
  if wait_gone "$monitor_pid"; then
    # "Nothing was reported" cannot be polled for: waiting for the view mode
    # NOT to appear only ends at the deadline, so this case used to spend its
    # full 4s on every green run. Instead a sentinel job fails on purpose, and
    # tmux appends its report to the same view after anything the monitor's
    # job put there -- its exit report, or output it printed -- so the view
    # must START with the sentinel's line. Judged by position, not by looking
    # for the monitor's words: those are a long path that wraps, and the view's
    # position indicator overwrites the end of the first row, so a match on
    # "monitor 'local-1'" only worked for a checkout path short enough to fit.
    #
    # The sentinel waits 0.5s before failing, as margin only: the monitor's pid
    # being gone need not mean tmux has finished its job, since an orphaned
    # child could still hold the job's output. Not observed -- on tmux 3.7c a
    # sentinel failing at once still came second, with the trap removed and a
    # 2s poll -- so the delay does not need to grow with the poll.
    #
    # Waited for by its own line, not by the view mode: a monitor that IS
    # reported puts the pane in the mode first.
    tmux -L "$INNER" run-shell -b 'sleep 0.5; exit 3'
    for _ in $(seq 1 40); do
      screen | grep -q "exit 3' returned 3" && break
      sleep 0.1
    done
    out=$(screen)
    first=${out%%$'\n'*}
    if ! printf '%s' "$out" | grep -q "exit 3' returned 3"; then
      fail_ "monitor: dying on SIGTERM leaves the screen alone" \
        "the sentinel's report never appeared, so nothing can be said:" "$out"
    else
      case "$first" in
        *"exit 3' returned 3"*) pass_ "monitor: dying on SIGTERM leaves the screen alone" ;;
        *) fail_ "monitor: dying on SIGTERM leaves the screen alone" \
          "the view starts with something before the sentinel's report:" "$out" ;;
      esac
    fi
  else
    fail_ "monitor: dying on SIGTERM leaves the screen alone" \
      "monitor pid $monitor_pid still alive after SIGTERM"
  fi
fi

# The pid file half, on a monitor whose file is still its own: the case above
# removes it first, as attach does, so it cannot see the trap's cleanup.
own_pid=$(start_inner_monitor local-2)
if [ -z "$own_pid" ]; then
  fail_ "monitor: removes its own pid file on SIGTERM" "it never wrote one"
else
  kill -TERM "$own_pid" 2>/dev/null
  wait_gone "$own_pid"
  if [ -e "$XDG_STATE_HOME/tmux-track-session/pid/local-2" ]; then
    fail_ "monitor: removes its own pid file on SIGTERM" "the file is still there"
  else
    pass_ "monitor: removes its own pid file on SIGTERM"
  fi
fi


# ---------------------------------------------------------------------------
# The subcommands nobody calls by hand. tmux-restore-ssh-tabs tells an old
# remote copy (no `adopt`) from one with nothing to adopt by this exit status:
# answered 0, an unknown subcommand reads as "no detached sessions". The legacy
# names are what old hooks in a running server still call, so they must stay a
# silent 0, or tmux shows "returned 1" in the pane.
# ---------------------------------------------------------------------------
"$SCRIPT" no-such-subcommand >/dev/null 2>"$DIR/usage.err"
t "an unknown subcommand exits 1" "1" "$?"
t "and prints the usage" "1" "$(grep -c '^Usage: tmux-track-session' "$DIR/usage.err")"
for legacy in register update cleanup; do
  "$SCRIPT" "$legacy" >"$DIR/legacy.out" 2>&1
  t "the legacy $legacy exits 0, silently" "0:" "$?:$(cat "$DIR/legacy.out")"
done

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
