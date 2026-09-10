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

DIR=$(mktemp -d)
export TMUX_TMPDIR="$DIR/tmux"
export XDG_STATE_HOME="$DIR/state"
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

command -v tmux >/dev/null || { echo "tmux is required" >&2; exit 1; }

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

record() { mkdir -p "$SESSION_DIR"; printf '%s' "$2" > "$SESSION_DIR/$1"; }
read_record() { cat "$SESSION_DIR/$1" 2>/dev/null || echo '<none>'; }
# Poll for a record to reach <expected> rather than sleeping a fixed amount and
# reading once. Returns as soon as it matches, so a pass is immediate and only a
# genuine failure pays the timeout -- and the value it echoes on timeout is the
# real one, so the failure report names what was actually there.
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

# script(1) is the only way to hand tmux a pty, and its command-line differs
# between BSD (macOS: `script -q <file> <cmd...>`) and util-linux (CI:
# `script -qec "<cmd>" <file>`). Probe rather than branch on the platform --
# macOS also ships util-linux via Homebrew.
if script -q /dev/null echo probe 2>/dev/null | grep -q probe; then
  in_pty() { script -q /dev/null "$@" >/dev/null 2>&1 & }
else
  in_pty() { script -qec "$*" /dev/null >/dev/null 2>&1 & }
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
record connA s1
record connB s2
"$SCRIPT" monitor connA "$ttyA" >/dev/null 2>&1 &
MONITOR_PIDS="$MONITOR_PIDS $!"
"$SCRIPT" monitor connB "$ttyB" >/dev/null 2>&1 &
MONITOR_PIDS="$MONITOR_PIDS $!"

# Wait for both monitors to be up before switching anything, by polling for the
# pid file each writes on the way into its loop. A fixed sleep here was a guess
# at how long two process starts take, and guessing wrong in the fast direction
# means the switch happens before anybody is watching for it -- which shows up
# much later, as the *next* assertion failing for no visible reason.
wait_running() { # wait_running <conn_id>
  for _ in $(seq 1 100); do
    [ -s "$PID_DIR/$1" ] && return 0
    sleep 0.1
  done
  echo "monitor for $1 never started" >&2
  return 1
}
wait_running connA || exit 1
wait_running connB || exit 1

tmux switch-client -c "$ttyB" -t '=s1'

# Poll rather than sleeping out two poll intervals. The second suite in this
# file already established why: a fixed read made its regression case pass green
# against the unfixed script, and the same hazard applies here -- the monitor is
# inside `sleep 2` when the switch lands, so how long this takes is not bounded
# by anything the test controls. wait_record returns the moment it matches and
# reports the real value if it never does.
t "monitor: the claimant records the session"   "s1"      "$(wait_record connB s1)"
t "monitor: the previous owner is released"     "<none>"  "$(wait_record connA '<none>')"

dupes=$(for f in "$SESSION_DIR"/*; do [ -f "$f" ] && { cat "$f"; echo; }; done | sort | uniq -d)
t "monitor: no two conn_ids name the same session" "" "$dupes"

kill_our_monitors
for p in $MONITOR_PIDS; do wait_gone "$p"; done
MONITOR_PIDS=""

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

# A record naming a session that no longer exists is pruned rather than kept.
record connE gone-session
record connF free
attach_as connF
t "attach: prunes a record naming a dead session" "<none>" "$(read_record connE)"

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
# This is the opposite direction from bin/pr-review-lock.sh, where `kill -0` is
# enough: there a recycled pid costs a missed steal, here it costs somebody
# else's process, so the pid has to be identified and not merely found alive.
sleep 600 &
bystander=$!
CLIENT_PIDS="$CLIENT_PIDS $bystander"
mkdir -p "$XDG_STATE_HOME/tmux-track-session/pid"
printf '%s' "$bystander" > "$XDG_STATE_HOME/tmux-track-session/pid/connH"
attach_as connH
t "attach: leaves an unrelated process holding a recycled pid alone" "alive" \
  "$(kill -0 "$bystander" 2>/dev/null && echo alive || echo dead)"

# The other half of the same decision: a pid that really is this conn_id's
# monitor must still be killed, or every reconnect leaks one.
"$SCRIPT" monitor connI "$ttyA" >/dev/null 2>&1 &
monitor_i=$!
CLIENT_PIDS="$CLIENT_PIDS $monitor_i"
for _ in $(seq 1 50); do [ -s "$XDG_STATE_HOME/tmux-track-session/pid/connI" ] && break; sleep 0.1; done
attach_as connI
gone=dead
for _ in $(seq 1 50); do kill -0 "$monitor_i" 2>/dev/null || break; sleep 0.1; done
kill -0 "$monitor_i" 2>/dev/null && gone=alive
t "attach: still kills this conn_id's own stale monitor" "dead" "$gone"

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
fail_() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; do printf '       %s\n' "$l"; done; fails=$((fails + 1)); }

tmux -L "$INNER" -f /dev/null new-session -d -s main -x 80 -y 24 "$IDLE"
tmux -L "$OUTER" -f /dev/null new-session -d -x 80 -y 24 "tmux -L $INNER attach -t main"

# Wait for the inner client to exist, otherwise the job has no one to report to.
client_tty=""
for _ in $(seq 1 50); do
  client_tty=$(tmux -L "$INNER" list-clients -F '#{client_tty}' 2>/dev/null | head -1)
  [ -n "$client_tty" ] && break
  sleep 0.1
done
[ -n "$client_tty" ] || { echo "inner client never attached" >&2; exit 1; }

# -J joins wrapped lines: the job's command is a long absolute path, so the
# report can be split mid-phrase across two rows of an 80-column screen.
screen() { tmux -L "$OUTER" capture-pane -pJ; }
clear_screen() { tmux -L "$INNER" send-keys -X cancel 2>/dev/null; }
in_mode() { tmux -L "$INNER" display-message -p -t main '#{pane_in_mode}'; }
# wait_mode 1 -- poll until the pane enters a mode, rather than sleeping a fixed
# amount and reading once. The delay between the job dying and the report
# reaching the screen is neither instant nor bounded by anything this test
# controls (the monitor is inside `sleep 2` when the signal lands, then the
# inner server renders, then the outer one does): a half-second read made the
# regression case pass green against the *unfixed* script, which is the one
# outcome this suite exists to prevent.
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
tmux -L "$INNER" run-shell -b "sleep 3117"
sanity_pid=""
for _ in $(seq 1 50); do
  sanity_pid=$(pgrep -f 'sleep 3117' | head -1)
  [ -n "$sanity_pid" ] && break
  sleep 0.1
done
if [ -z "$sanity_pid" ]; then
  fail_ "harness: a signalled run-shell job is visible on the client" "the sanity job never started"
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
  clear_screen
fi

conn_id="local-1"
tmux -L "$INNER" run-shell -b "'$SCRIPT' monitor '$conn_id' '$client_tty'"

pid_file="$XDG_STATE_HOME/tmux-track-session/pid/$conn_id"
monitor_pid=""
for _ in $(seq 1 50); do
  [ -s "$pid_file" ] && monitor_pid=$(cat "$pid_file")
  [ -n "$monitor_pid" ] && break
  sleep 0.1
done

if [ -z "$monitor_pid" ]; then
  fail_ "monitor: starts and records its pid" "no pid in $pid_file"
else
  pass_ "monitor: starts and records its pid"

  # This is exactly what `attach` does to the previous connection's monitor.
  kill -TERM "$monitor_pid" 2>/dev/null
  if wait_gone "$monitor_pid"; then
    # The view mode is the visible half of the bug: it covers the pane and
    # waits for a keypress. This waits out the full timeout on a pass, which is
    # what buys the assertion its meaning.
    if wait_mode 1; then
      fail_ "monitor: dying on SIGTERM leaves the pane out of view mode" \
        "the pane entered a mode, so tmux reported the job's death over the remote screen"
    else
      pass_ "monitor: dying on SIGTERM leaves the pane out of view mode"
    fi

    out=$(screen)
    if printf '%s' "$out" | grep -q 'terminated by signal'; then
      fail_ "monitor: dying on SIGTERM leaves the screen alone" \
        "tmux reported the job's death onto the remote screen:" \
        "$(printf '%s' "$out" | grep 'terminated by signal')"
    else
      pass_ "monitor: dying on SIGTERM leaves the screen alone"
    fi

    if [ -e "$pid_file" ]; then
      fail_ "monitor: removes its pid file on SIGTERM" "$pid_file still exists"
    else
      pass_ "monitor: removes its pid file on SIGTERM"
    fi
  else
    fail_ "monitor: dying on SIGTERM leaves the screen alone" \
      "monitor pid $monitor_pid still alive after SIGTERM"
  fi
fi

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
