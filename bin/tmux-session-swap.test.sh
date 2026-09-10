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

command -v tmux >/dev/null || {
  echo "tmux is required" >&2
  exit 1
}

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
# How many clients a session holds. Used where the interesting fact is that
# *somebody* moved, rather than which particular client did.
#
# list-sessions, not `display-message -p -t "=$1"`: display-message expands a
# session format against a *client*, so with nothing attached to the session it
# prints an empty string and exits 0 rather than "0". That reads as a passing
# comparison against another empty string, which is the wrong kind of quiet.
attached_on() { tmux list-sessions -f "#{==:#{session_name},$1}" -F '#{session_attached}'; }

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
t "swap: the picker lands on its choice" "bravo" "$(where "$ttyA")"
t "swap: the incumbent takes the vacated one" "alpha" "$(where "$ttyB")"
t "swap: no session ends up with two clients" "" "$(doubled)"

# --- picking a free session: a plain move, nobody else is touched ------------
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go idle
t "free: the picker lands on its choice" "idle" "$(where "$ttyA")"
t "free: the other client is left alone" "alpha" "$(where "$ttyB")"
t "free: no session ends up with two clients" "" "$(doubled)"

# --- a window target, which is what choose-tree -Zw actually passes ----------
win=$(tmux list-windows -t '=alpha' -F '#{session_name}:#{window_index}' | head -1)
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go "$win"
t "window target: resolved to its session" "alpha" "$(where "$ttyA")"
t "window target: the incumbent was swapped" "idle" "$(where "$ttyB")"
t "window target: no session has two clients" "" "$(doubled)"

# --- picking the session you are already on is a no-op ----------------------
before=$(where "$ttyA")
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go "$before"
t "same session: nothing moves" "$before" "$(where "$ttyA")"
t "same session: no session has two clients" "" "$(doubled)"

# --- without an arm it degrades to a plain switch, not to nothing -----------
#
# The exit status proves nothing on its own: that branch ends in an
# unconditional `exit 0` and sends switch-client's own status to /dev/null, so
# an assertion on $? passes even when the branch does nothing whatsoever --
# confirmed by replacing its body with `:`, which left the suite green. What is
# actually observable is that the target session gains a client.
#
# The assertion is on the target, not on a particular tty, because *which*
# client moves is tmux's decision rather than this script's: there is no
# recorded tty to move, so `switch-client` with no -c resolves the current
# client itself (measured here: the most recently attached one).
#
# A session of its own, rather than one of the sessions above, so the case does
# not depend on where the previous cases happened to leave the two clients.
tmux new-session -d -s spare "$IDLE"
rm -f "$XDG_STATE_HOME/tmux-session-swap/armed"
before_spare=$(attached_on spare)
"$SCRIPT" go spare >/dev/null 2>&1
t "unarmed: exits cleanly" "0" "$?"
t "unarmed: the target session gains a client" "0 -> 1" "$before_spare -> $(attached_on spare)"

# --- a target that no longer exists is ignored rather than erroring ---------
pos=$(where "$ttyA")
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go no-such-session >/dev/null 2>&1
t "dead target: the picker did not move" "$pos" "$(where "$ttyA")"
# `go` consumes the arm, on every path. The dead-target branch used to return
# before reaching the removal, so a pick that resolved to nothing left the tty
# on disk. Harmless in the binding, which re-arms before every chooser, but it
# means the file no longer says "a chooser is open right now" -- and that is the
# only thing it is for.
t "dead target: the arm was consumed anyway" "gone" \
  "$([ -f "$XDG_STATE_HOME/tmux-session-swap/armed" ] && echo left-behind || echo gone)"

# --- anything that is not arm or go is a usage error ------------------------
# A silent exit 0 here would look exactly like a working key, which is the same
# reason bin/tmux-popup.test.sh pins its own usage path.
out=$("$SCRIPT" wobble 2>&1)
rc=$?
t "unknown subcommand: exits non-zero" "1" "$rc"
t "unknown subcommand: says how to call it" "usage" "$(case "$out" in *Usage*) echo usage ;; *) echo "silent: $out" ;; esac)"

# --- more than one client on the chosen session ------------------------------
#
# The loop over clients_on() exists for this, and every case above exercises it
# with exactly one incumbent -- which the simplest possible wrong implementation
# (move the first one, ignore the rest) also handles. Two incumbents is not a
# contrived state: it is what tmux's own `w` produces, and what an earlier
# bin/tmux-track-session bug produced on reconnect, so the repair path is the
# reason to reach for this key rather than switch-client.
#
# What is promised here is about the *chosen* session, not about the whole
# server: every client that was on it is moved off, so the picker lands there
# alone. The doubling itself moves to the vacated session rather than being
# cured -- a one-for-one swap cannot turn three clients into three sessions --
# and asserting otherwise would pin behaviour this does not have.
tmux new-session -d -s crowd "$IDLE"
tmux new-session -d -s lonely "$IDLE"
new_client crowd || exit 1
ttyC=$(tty_on crowd) # read before crowd gains a second
tmux switch-client -c "$ttyB" -t '=crowd'
tmux switch-client -c "$ttyA" -t '=lonely'
"$SCRIPT" arm "$ttyA"
"$SCRIPT" go crowd
t "crowded target: the picker ends up on it alone" "1" "$(attached_on crowd)"
t "crowded target: and the picker is who is there" "crowd" "$(where "$ttyA")"
t "crowded target: every incumbent was moved off" "lonely lonely" \
  "$(where "$ttyB") $(where "$ttyC")"

# Not covered on purpose: the branch taken when the picking client vanished
# between arm and go (`from_session` empty). Removing that guard changes
# nothing observable -- the loop's switch-client is then handed an empty target
# and fails, and so does the final one, leaving every client exactly where the
# guard would have left them. A case asserting that outcome would pass with or
# without the branch, which is the kind of assertion this file has one of too
# many already.

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
