#!/usr/bin/env bash
# Tests for bin/tmux-track-session — specifically that its monitor dies quietly.
#
# The monitor runs as a tmux `run-shell -b` job on the remote, and tmux reports
# such a job that dies by a signal as "'<cmd>' terminated by signal 15", opening
# that report in a **view mode covering the pane**. `attach` TERMs the previous
# connection's monitor on every reconnect, so the report landed on the remote
# screen every time the link came back — over whatever was drawn there, needing
# a keypress to dismiss. That is a display bug with no error anywhere, which is
# why it is pinned here rather than left to be noticed.
#
# Two tmux servers, not one, and that is the whole harness: tmux hands a
# run-shell job's output to a *client*, so with nothing attached the message is
# never rendered and every assertion below passes vacuously. The outer server
# exists only to supply the pty the inner one is attached through, and the
# assertions read the inner screen by capturing the outer pane.
#
# Requires tmux; fails rather than skips without it.
#
# Run: bash bin/tmux-track-session.test.sh   (exit 0 = pass)
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
script="$PWD/bin/tmux-track-session"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux-track-session.test: tmux is required" >&2
  exit 1
fi

inner="track-inner-$$"
outer="track-outer-$$"
work=$(mktemp -d)
cleanup() {
  tmux -L "$inner" kill-server 2>/dev/null
  tmux -L "$outer" kill-server 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; do printf '  %s\n' "$l"; done; failures=$((failures + 1)); }

# The pane runs `sleep`, never a shell: the shell these dotfiles install has a
# precmd hook that writes pane options, which is noise the screen assertions
# below would have to tolerate. Same reason as in tmux-pane-titles.test.sh.
IDLE='sleep 300'

# The inner server is the "remote": XDG_STATE_HOME is set on it so the monitor,
# which inherits the server's environment, keeps its state inside $work.
XDG_STATE_HOME="$work/state" \
  tmux -L "$inner" -f /dev/null new-session -d -s main -x 80 -y 24 "$IDLE"
tmux -L "$outer" -f /dev/null new-session -d -x 80 -y 24 "tmux -L $inner attach -t main"

# Wait for the inner client to exist, otherwise the job has no one to report to.
client_tty=""
for _ in $(seq 1 50); do
  client_tty=$(tmux -L "$inner" list-clients -F '#{client_tty}' 2>/dev/null | head -1)
  [ -n "$client_tty" ] && break
  sleep 0.1
done
[ -n "$client_tty" ] || { echo "tmux-track-session.test: inner client never attached" >&2; exit 1; }

# -J joins wrapped lines: the job's command is a long absolute path, so the
# report can be split mid-phrase across two rows of an 80-column screen.
screen() { tmux -L "$outer" capture-pane -pJ; }
clear_screen() { tmux -L "$inner" send-keys -X cancel 2>/dev/null; }
in_mode() { tmux -L "$inner" display-message -p -t main '#{pane_in_mode}'; }
wait_gone() { # wait_gone <pid>
  local _i
  for _i in $(seq 1 50); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}

# wait_mode 1 — poll until the pane enters a mode, rather than sleeping a fixed
# amount and reading once. The delay between the job dying and the report
# reaching the screen is neither instant nor bounded by anything this test
# controls (the monitor is inside `sleep 2` when the signal lands, then the
# inner server renders, then the outer one does): a half-second read made the
# regression case pass green against the *unfixed* script, which is the one
# outcome this file exists to prevent.
wait_mode() {
  local _i
  for _i in $(seq 1 40); do
    [ "$(in_mode)" = "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

# --- the harness itself: a signalled job DOES reach the screen -------------
# Without this case a broken reproduction (nothing attached, wrong socket, a
# capture that reads the wrong pane) would make the real assertion below pass
# while proving nothing.
tmux -L "$inner" run-shell -b "sleep 3117"
sanity_pid=""
for _ in $(seq 1 50); do
  sanity_pid=$(pgrep -f 'sleep 3117' | head -1)
  [ -n "$sanity_pid" ] && break
  sleep 0.1
done
if [ -z "$sanity_pid" ]; then
  fail "harness: a signalled run-shell job is visible on the client" "the sanity job never started"
else
  kill -TERM "$sanity_pid" 2>/dev/null
  wait_gone "$sanity_pid"
  wait_mode 1
  if screen | grep -q 'terminated by signal'; then
    pass "harness: a signalled run-shell job is visible on the client"
  else
    fail "harness: a signalled run-shell job is visible on the client" \
      "expected 'terminated by signal' on the inner screen; the harness cannot see the bug it tests for"
  fi
  clear_screen
fi

# --- the regression: the monitor must not be one of those jobs ------------
conn_id="local-1"
tmux -L "$inner" run-shell -b "'$script' monitor '$conn_id' '$client_tty'"

pid_file="$work/state/tmux-track-session/pid/$conn_id"
monitor_pid=""
for _ in $(seq 1 50); do
  [ -s "$pid_file" ] && monitor_pid=$(cat "$pid_file")
  [ -n "$monitor_pid" ] && break
  sleep 0.1
done

if [ -z "$monitor_pid" ]; then
  fail "monitor: starts and records its pid" "no pid in $pid_file"
else
  pass "monitor: starts and records its pid"

  # This is exactly what `attach` does to the previous connection's monitor.
  kill -TERM "$monitor_pid" 2>/dev/null
  if wait_gone "$monitor_pid"; then
    # The view mode is the visible half of the bug: it covers the pane and
    # waits for a keypress. This waits out the full timeout on a pass, which is
    # what buys the assertion its meaning.
    if wait_mode 1; then
      fail "monitor: dying on SIGTERM leaves the pane out of view mode" \
        "the pane entered a mode, so tmux reported the job's death over the remote screen"
    else
      pass "monitor: dying on SIGTERM leaves the pane out of view mode"
    fi

    out=$(screen)
    if printf '%s' "$out" | grep -q 'terminated by signal'; then
      fail "monitor: dying on SIGTERM leaves the screen alone" \
        "tmux reported the job's death onto the remote screen:" \
        "$(printf '%s' "$out" | grep 'terminated by signal')"
    else
      pass "monitor: dying on SIGTERM leaves the screen alone"
    fi

    if [ -e "$pid_file" ]; then
      fail "monitor: removes its pid file on SIGTERM" "$pid_file still exists"
    else
      pass "monitor: removes its pid file on SIGTERM"
    fi
  else
    fail "monitor: dying on SIGTERM leaves the screen alone" \
      "monitor pid $monitor_pid still alive after SIGTERM"
  fi
fi

if [ "$failures" -gt 0 ]; then
  printf '\n%d failure(s)\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
