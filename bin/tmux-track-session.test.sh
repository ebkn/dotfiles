#!/bin/bash
#
# tmux-track-session.test.sh
#
# Covers the two-way exclusivity of the conn_id <-> session binding: one conn_id
# names one session, and one session is named by at most one conn_id. Losing
# either direction is silent -- the symptom is two WezTerm tabs mirroring the
# same remote session some minutes later, after an autossh reconnect, with
# nothing at the moment of the switch to suggest what happened.
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
SCRIPT="$(cd "$(dirname "$0")" && pwd)/tmux-track-session"
IDLE='sleep 600'
CLIENT_PIDS=""
fails=0

command -v tmux >/dev/null || { echo "tmux is required" >&2; exit 1; }

cleanup() {
  for p in $CLIENT_PIDS; do kill "$p" 2>/dev/null; done
  pkill -f "tmux-track-session monitor" 2>/dev/null
  tmux kill-server 2>/dev/null
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
"$SCRIPT" monitor connB "$ttyB" >/dev/null 2>&1 &
sleep 1
tmux switch-client -c "$ttyB" -t '=s1'
sleep 4   # the monitor polls every 2s

t "monitor: the claimant records the session"   "s1"      "$(read_record connB)"
t "monitor: the previous owner is released"     "<none>"  "$(read_record connA)"

dupes=$(for f in "$SESSION_DIR"/*; do [ -f "$f" ] && { cat "$f"; echo; }; done | sort | uniq -d)
t "monitor: no two conn_ids name the same session" "" "$dupes"

pkill -f "tmux-track-session monitor" 2>/dev/null
sleep 0.5

# ---------------------------------------------------------------------------
# attach: resolution. It ends in `exec tmux new-session -A`, which attaches, so
# it is run under a pty like any other client and the assertions are on where it
# landed.
# ---------------------------------------------------------------------------
attach_as() { # attach_as <conn_id>
  in_pty "$SCRIPT" attach "$1"
  CLIENT_PIDS="$CLIENT_PIDS $!"
  sleep 3
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
attach_as connD
t "attach: does not join a session another client holds" "1" \
  "$(tmux list-sessions -F '#{session_name} #{session_attached}' | grep -c '^held 1$')"
t "attach: falls back to its own conn_id session" "1" \
  "$(tmux list-sessions -F '#{session_name} #{session_attached}' | grep -c '^connD 1$')"

# A record naming a session that no longer exists is pruned rather than kept.
record connE gone-session
record connF free
attach_as connF
t "attach: prunes a record naming a dead session" "<none>" "$(read_record connE)"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
