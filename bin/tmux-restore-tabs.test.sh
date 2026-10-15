#!/bin/bash
#
# tmux-restore-tabs.test.sh
#
# The contract: one WezTerm tab per unattached tmux session, attached to that
# session by its exact name, spawned into the window the user ran it from, and
# focus handed back to the pane they ran it from.
#
# Two regressions, both found live after a crash:
#
# (1) Every tab opened in a NEW WINDOW. `wezterm cli spawn` picks its window
#     from $WEZTERM_PANE, and inside tmux that is whatever the tmux server
#     inherited when it started -- after WezTerm restarts it names a pane of the
#     previous WezTerm. The pane has to come from WezTerm itself.
# (2) Session names were cut out of the listing with awk's index($0, $3), which
#     finds the FIRST occurrence of the name on the line -- inside the
#     timestamp, for a numeric name like "35" on "1790660355 0 35". The tab then
#     attached to "355 0 35", which does not exist.
#
# The tmux server is real and isolated. TMUX is unset, not just TMUX_TMPDIR set:
# tmux prefers the socket named in $TMUX, so a run inside tmux would otherwise
# create -- and at cleanup, kill -- sessions on the developer's own server.
# wezterm is a stub; it cannot run on a CI runner.

set -u
# A tmux suite: container or CI only (see bin/tmux-test-guard.sh).
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2
# shellcheck source=bin/test-lib.sh
. "$(dirname "$0")/test-lib.sh" || exit 2

DIR=$(mktemp -d)
export TMUX_TMPDIR="$DIR/tmux"
unset TMUX TMUX_PANE
# The stale value regression (1) is about. Nothing may read it.
export WEZTERM_PANE=999
mkdir -p "$TMUX_TMPDIR" "$DIR/stub"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/tmux-restore-tabs"
IDLE='sleep 600'
CLIENT_PID=""
fails=0

cleanup() {
  [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null
  tmux kill-server 2>/dev/null
  rm -rf "$DIR"
}
trap cleanup EXIT

command -v tmux >/dev/null || {
  echo "tmux is required" >&2
  exit 1
}

# Three GUI clients; the one idle for least time is the one the user just typed
# into, so its focused pane (42) is where the tabs belong. It sits in the
# MIDDLE of the list, so neither "the first" nor "the last" client finds it by
# accident. Spawns and focus changes are recorded, and so is the socket each
# call was made against.
cat >"$DIR/stub/wezterm" <<'STUB'
#!/bin/sh
printf '%s\n' "$WEZTERM_UNIX_SOCKET" >>"$CALLS.sock"
if [ "$1 $2" = "cli list-clients" ]; then
  cat <<'JSON'
[{"focused_pane_id":5,"idle_time":{"secs":900,"nanos":0}},
 {"focused_pane_id":42,"idle_time":{"secs":1,"nanos":500}},
 {"focused_pane_id":8,"idle_time":{"secs":30,"nanos":0}}]
JSON
  exit 0
fi
printf '%s\n' "$*" >>"$CALLS"
STUB
chmod +x "$DIR/stub/wezterm"
export CALLS="$DIR/calls"
: >"$CALLS"

t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# Creation order against name order: zz-oldest is created a second before the
# rest and aa-newest a second after, so "oldest first" -- the order the tabs had
# before the crash -- is the reverse of the alphabetical order list-sessions
# uses. session_created has one-second resolution, hence the waits -- for the
# clock to pass the given session's second, half a second on average, where a
# fixed `sleep 1` always paid the whole one.
# next_second (bin/test-lib.sh) does the waiting; this reads the stamp.
created_of() { tmux display-message -p -t "=$1:" '#{session_created}'; }
tmux -f /dev/null new-session -d -s zz-oldest "$IDLE"
next_second "$(created_of zz-oldest)"
tmux new-session -d -s placeholder "$IDLE"
# A name that also occurs inside its own session_created timestamp: three
# digits from the middle of it, which is what regression (2) needs.
created=$(tmux display-message -p -t '=placeholder:' '#{session_created}')
numeric=$(printf '%s' "$created" | cut -c 5-7)
tmux rename-session -t '=placeholder' "$numeric"
t "harness: the numeric name is three digits of its own timestamp" "yes" \
  "$(case "$numeric" in [0-9][0-9][0-9]) case "$created" in *"$numeric"*) echo yes ;; esac ;; esac)"
tmux new-session -d -s 'my work' "$IDLE"
tmux new-session -d -s held "$IDLE"
# Popup sessions (bin/tmux-popup's `_<name>_<id>`, tmux-agent-view's
# `_agent_...`) outlive their popup unattached, and never had a tab of their own:
# restoring one would open a tab on a popup's shell. Skipped like `adopt` does.
tmux new-session -d -s _popup_9 "$IDLE"
tmux new-session -d -s _agent_3_99 "$IDLE"
# Only a LEADING underscore marks a popup. A glob loosened to `*_*` would drop
# an ordinary session like this one, silently.
tmux new-session -d -s tidy_up "$IDLE"
next_second "$(created_of tidy_up)"
tmux new-session -d -s aa-newest "$IDLE"

# A real client on `held`, so it counts as attached. script(1) differs between
# BSD and util-linux; probe rather than branch on the platform.
if script -q /dev/null echo probe 2>/dev/null | grep -q probe; then
  env TERM=xterm-256color script -q /dev/null tmux attach -t =held >/dev/null 2>&1 &
else
  env TERM=xterm-256color script -qec "tmux attach -t =held" /dev/null >/dev/null 2>&1 &
fi
CLIENT_PID=$!
for _ in $(seq 1 50); do
  [ "$(tmux list-clients -F x 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && break
  sleep 0.1
done
t "harness: held has a client" "1" "$(tmux display-message -p -t '=held:' '#{session_attached}')"

# Run with the dead socket a tmux session inherits after WezTerm restarts.
: >"$CALLS.sock"
PATH="$DIR/stub:$PATH" WEZTERM_UNIX_SOCKET=/stale/gui-sock "$SCRIPT" >/dev/null 2>&1
status=$?

spawns=$(grep '^cli spawn' "$CALLS")
t "exits 0" "0" "$status"
t "a numeric name found inside the timestamp is attached exactly" "1" \
  "$(printf '%s\n' "$spawns" | grep -cx "cli spawn --pane-id 42 -- tmux attach -t =$numeric")"
t "a name with a space is attached exactly" "1" \
  "$(printf '%s\n' "$spawns" | grep -cx "cli spawn --pane-id 42 -- tmux attach -t =my work")"
t "an attached session gets no tab" "0" "$(printf '%s\n' "$spawns" | grep -c 'held')"
t "a popup session gets no tab" "0" "$(printf '%s\n' "$spawns" | grep -c -- '-t =_')"
t "an underscore inside a name is not a popup" "1" \
  "$(printf '%s\n' "$spawns" | grep -cx "cli spawn --pane-id 42 -- tmux attach -t =tidy_up")"
t "every tab goes into the focused client's window, never \$WEZTERM_PANE's" "5" \
  "$(printf '%s\n' "$spawns" | grep -c -- '--pane-id 42 ')"
t "focus returns to the focused pane" "cli activate-pane --pane-id 42" "$(tail -1 "$CALLS")"
# Oldest first, which is the tab order before the crash.
t "the oldest session's tab opens first" "=zz-oldest" \
  "$(printf '%s\n' "$spawns" | head -n 1 | sed 's/.* -t //')"
t "and the newest one's last" "=aa-newest" \
  "$(printf '%s\n' "$spawns" | tail -n 1 | sed 's/.* -t //')"
t "every wezterm call uses the socket symlink, not the inherited one" \
  "$HOME/.local/share/wezterm/default-org.wezfurlong.wezterm" "$(sort -u "$CALLS.sock")"

# Nothing to restore: every remaining session has a client, or is a popup's --
# the two popup sessions above are still there, unattached, so this is also
# what proves they are dropped BEFORE the empty check rather than after it.
# This is what a second run looks like, and the path the session loop's rewrite runs through
# with empty input -- its last iteration ends non-zero, which under `set -e`
# must still reach the message rather than exit quietly.
tmux kill-session -t "=$numeric"
tmux kill-session -t '=my work'
tmux kill-session -t '=tidy_up'
tmux kill-session -t '=zz-oldest'
tmux kill-session -t '=aa-newest'
: >"$CALLS"
out=$(PATH="$DIR/stub:$PATH" "$SCRIPT" 2>&1)
status=$?
t "nothing to restore: exits 1" "1" "$status"
t "nothing to restore: says so" "No unattached tmux sessions found" "$out"
t "nothing to restore: opens nothing" "" "$(cat "$CALLS")"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
