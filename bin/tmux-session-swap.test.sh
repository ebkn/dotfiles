#!/bin/bash
#
# tmux-session-swap.test.sh
#
# Pins the invariant the script exists for: after a switch, every session has at
# most one client, and no client has been left without a session. tmux's own
# `w` breaks both halves at once -- it puts a second client on the chosen
# session and leaves the one you came from empty -- and neither is visible at
# the moment it happens. The tab you switched away from simply starts echoing
# somebody else's keystrokes some minutes later.
#
# Real throwaway server, real pty clients via script(1). A stubbed tmux could
# only check the command line the script decides, and the thing worth checking
# is the client-to-session mapping tmux is left holding. Isolation is
# TMUX_TMPDIR, not -L, because the script calls bare `tmux`; TMUX must be unset
# because tmux refuses a nested attach.

set -u

DIR=$(mktemp -d)
export TMUX_TMPDIR="$DIR/tmux"
export XDG_STATE_HOME="$DIR/state"
unset TMUX TMUX_PANE
mkdir -p "$TMUX_TMPDIR"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/tmux-session-swap"
IDLE='sleep 600'
CLIENT_PIDS=""
fails=0

command -v tmux >/dev/null || { echo "tmux is required" >&2; exit 1; }

cleanup() {
  for p in $CLIENT_PIDS; do kill "$p" 2>/dev/null; done
  tmux kill-server 2>/dev/null
  rm -rf "$DIR"
}
trap cleanup EXIT

t() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
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
where() { tmux list-clients -f "#{==:#{client_tty},$1}" -F '#{client_session}'; }
# Sessions holding more than one client, one per line. Must always be empty.
doubled() { tmux list-sessions -f '#{>:#{session_attached},1}' -F '#{session_name}'; }

tmux -f /dev/null new-session -d -s alpha "$IDLE"
tmux set -g default-command "$IDLE"
tmux new-session -d -s bravo "$IDLE"
tmux new-session -d -s idle "$IDLE"

new_client alpha || exit 1
new_client bravo || exit 1
ttyA=$(tty_on alpha)
ttyB=$(tty_on bravo)

# --- picking a session another client holds: the two clients swap ------------
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go bravo
t "swap: the picker lands on its choice"        "bravo"  "$(where "$ttyA")"
t "swap: the incumbent takes the vacated one"   "alpha"  "$(where "$ttyB")"
t "swap: no session ends up with two clients"   ""       "$(doubled)"

# --- picking a free session: a plain move, nobody else is touched ------------
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go idle
t "free: the picker lands on its choice"        "idle"   "$(where "$ttyA")"
t "free: the other client is left alone"        "alpha"  "$(where "$ttyB")"
t "free: no session ends up with two clients"   ""       "$(doubled)"

# --- a window target, which is what choose-tree -Zw actually passes ----------
win=$(tmux list-windows -t '=alpha' -F '#{session_name}:#{window_index}' | head -1)
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go "$win"
t "window target: resolved to its session"      "alpha"  "$(where "$ttyA")"
t "window target: the incumbent was swapped"    "idle"   "$(where "$ttyB")"
t "window target: no session has two clients"   ""       "$(doubled)"

# --- picking the session you are already on is a no-op ----------------------
before=$(where "$ttyA")
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go "$before"
t "same session: nothing moves"                 "$before" "$(where "$ttyA")"
t "same session: no session has two clients"    ""        "$(doubled)"

# --- without an arm it degrades to a plain switch, not to nothing -----------
rm -f "$XDG_STATE_HOME/tmux-session-swap/armed"
t "unarmed: the key still does something"       "0"       "$("$SCRIPT" go idle >/dev/null 2>&1; echo $?)"

# --- a target that no longer exists is ignored rather than erroring ---------
pos=$(where "$ttyA")
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go no-such-session >/dev/null 2>&1
t "dead target: the picker did not move"        "$pos"    "$(where "$ttyA")"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
