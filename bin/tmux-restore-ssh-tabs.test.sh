#!/bin/bash
#
# tmux-restore-ssh-tabs.test.sh
#
# The contract: one WezTerm tab per remote session `adopt` prints, in its order,
# each attached to a local tmux session of its own whose shell was handed
# `MYSSH_SESSION=<session> myssh <host>`. And when the remote cannot answer,
# nothing is opened -- an old tmux-track-session without `adopt` must fail
# loudly rather than look like "no sessions".
#
# The local tmux is real, on a server of its own (TMUX_TMPDIR, since the script
# calls bare tmux), with `cat` as every pane's command: the pty echoes what the
# script typed, so the line can be read back with capture-pane and then run
# through zsh the way the pane's shell would. ssh and wezterm are stubs -- the
# remote half is pinned by tmux-track-session.test.sh, and WezTerm cannot run
# on a CI runner at all.

set -u
# A tmux suite: container or CI only (see bin/tmux-test-guard.sh).
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2

DIR=$(mktemp -d)
export TMUX_TMPDIR="$DIR/tmux"
unset TMUX TMUX_PANE
mkdir -p "$TMUX_TMPDIR" "$DIR/stub"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/tmux-restore-ssh-tabs"
fails=0

cleanup() {
  tmux kill-server 2>/dev/null
  rm -rf "$DIR"
}
trap cleanup EXIT

command -v tmux >/dev/null || {
  echo "tmux is required" >&2
  exit 1
}

# ssh records the command it was asked to run, then really runs it, as the
# remote shell would, against a remote $HOME whose tmux-track-session prints
# $ADOPT and exits $ADOPT_EXIT. Running it rather than faking its output is
# what lets a case see whether the success marker is tied to adopt's status.
# ssh exits with the command's status, unless $SSH_EXIT overrides it: 255 for a
# dropped connection, 0 for Tailscale SSH, which reports 0 for everything.
# wezterm answers `cli list-clients` with two GUI clients, the less idle one
# focused on pane 7, and records everything else.
cat >"$DIR/stub/ssh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$CALLS"
shift
HOME="$REMOTE_HOME" sh -c "$*"
rc=$?
exit "${SSH_EXIT:-$rc}"
STUB
export REMOTE_HOME="$DIR/remote"
mkdir -p "$REMOTE_HOME/.local/bin"
cat >"$REMOTE_HOME/.local/bin/tmux-track-session" <<'STUB'
#!/bin/sh
[ "$1" = adopt ] || exit 1
[ -n "$ADOPT" ] && printf '%s\n' "$ADOPT"
exit "${ADOPT_EXIT:-0}"
STUB
chmod +x "$REMOTE_HOME/.local/bin/tmux-track-session"
cat >"$DIR/stub/wezterm" <<'STUB'
#!/bin/sh
if [ "$1 $2" = "cli list-clients" ]; then
  echo '[{"focused_pane_id":3,"idle_time":{"secs":600,"nanos":0}},{"focused_pane_id":7,"idle_time":{"secs":2,"nanos":0}}]'
  exit 0
fi
printf 'wezterm %s\n' "$*" >>"$CALLS"
STUB
chmod +x "$DIR/stub"/*
export CALLS="$DIR/calls"

t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# A server that outlives the cases, whose panes run `cat`.
tmux -f /dev/null new-session -d -s keep 'sleep 600'
tmux set -g default-command cat

run() { # run <adopt output> [adopt exit] [ssh exit] -- sets $status and $out
  : >"$CALLS"
  out=$(PATH="$DIR/stub:$PATH" ADOPT="$1" ADOPT_EXIT="${2:-0}" SSH_EXIT="${3:-}" \
    "$SCRIPT" myhost 2>&1)
  status=$?
}

sessions_but_keep() { tmux list-sessions -F '#{session_name}' | grep -vx keep; }

# The line typed into <session>'s pane, once cat has echoed it back.
typed() {
  local line
  for _ in $(seq 1 50); do
    line=$(tmux capture-pane -p -t "=$1:" | grep myssh | head -1)
    [ -n "$line" ] && break
    sleep 0.1
  done
  printf '%s' "$line"
}

# What the pane's zsh would do with the typed line: which session and host
# myssh would be called with.
as_zsh_runs() {
  zsh -f -c "myssh() { printf '%s|%s' \"\$MYSSH_SESSION\" \"\$1\"; }; $1"
}

# ---------------------------------------------------------------------------
run "$(printf 'zeta\nmy work')"
# The first three words only: the host, and the path adopt is run by. What
# follows is the success marker, which the failure cases below pin by what it
# does rather than by how it is spelled.
t "runs adopt on the named host" \
  "myhost ~/.local/bin/tmux-track-session adopt" \
  "$(grep -v '^wezterm' "$CALLS" | cut -d' ' -f1-3)"
t "exits 0 when tabs were opened" "0" "$status"

locals=$(sessions_but_keep)
t "one local session per adopted session" "2" "$(printf '%s\n' "$locals" | grep -c .)"

spawned=$(grep '^wezterm cli spawn' "$CALLS" | sed 's/.*-t =//')
t "one tab per local session, attached to it" \
  "$(printf '%s\n' "$locals" | sort)" "$(printf '%s\n' "$spawned" | sort)"

first=$(printf '%s\n' "$spawned" | sed -n 1p)
second=$(printf '%s\n' "$spawned" | sed -n 2p)
t "tabs open in adopt's order (first)" "zeta|myhost" "$(as_zsh_runs "$(typed "$first")")"
t "a session name with a space survives the pane's shell" \
  "my work|myhost" "$(as_zsh_runs "$(typed "$second")")"

t "every tab goes into the focused client's window" "2" \
  "$(grep -c '^wezterm cli spawn --pane-id 7 -- ' "$CALLS")"
t "focus returns to the tab it was run from" \
  "wezterm cli activate-pane --pane-id 7" "$(tail -1 "$CALLS")"

for s in $locals; do tmux kill-session -t "=$s"; done

# ---------------------------------------------------------------------------
# The marker arrived, but ssh exited 255 -- a connection lost after the
# listing. The only case where the status check alone refuses, so it is what
# keeps that check from being dropped as redundant with the marker.
run "zeta" 0 255
t "a failure status from ssh exits non-zero, even with the marker" "1" "$status"
t "a failure status from ssh says which host" "1" "$(printf '%s' "$out" | grep -c 'could not adopt sessions on myhost')"
t "a failure status from ssh opens nothing, even with the marker" "" "$(
  sessions_but_keep
  grep '^wezterm' "$CALLS"
)"

# Tailscale SSH reports exit status 0 whatever the remote command returned
# (measured against a macOS host: `ssh <host> 'exit 3'` exits 0), so a remote
# tmux-track-session too old to know `adopt` -- usage on stderr, nothing on
# stdout, exit 1 -- arrives looking exactly like "no sessions". The script must
# still tell them apart.
run "" 1 0
t "a failed adopt behind an ssh that always exits 0 exits non-zero" "1" "$status"
t "a failed adopt behind an ssh that always exits 0 says adopt failed" "1" \
  "$(printf '%s' "$out" | grep -c 'could not adopt sessions on myhost')"
t "a failed adopt behind an ssh that always exits 0 opens nothing" "" "$(
  sessions_but_keep
  grep '^wezterm' "$CALLS"
)"

run "zeta" 1 0
t "partial output behind an ssh that always exits 0 opens nothing" "" "$(
  sessions_but_keep
  grep '^wezterm' "$CALLS"
)"

run ""
t "no free sessions exits non-zero" "1" "$status"
t "no free sessions says so, not that adopt failed" "1" \
  "$(printf '%s' "$out" | grep -c 'No detached tmux sessions on myhost')"
t "no free sessions opens nothing" "" "$(
  sessions_but_keep
  grep '^wezterm' "$CALLS"
)"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
