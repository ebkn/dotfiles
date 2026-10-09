#!/bin/bash
#
# tmux-tig.test.sh
#
# The contract (bin/tmux-popup.md): when tig succeeds, tmux-tig exits with no
# pause; when tig fails, its own message stays on screen with a pause line, the
# script waits for ONE key, and exits with tig's status. The bug this exists for
# was a popup that vanished with the error unread, so the case that matters is
# "still running until the key arrives", not the exit status.
#
# tig is a stub. The pause reads from /dev/tty, so the script runs under
# script(1) for a real pty, with its input fed through a fifo: holding the fifo
# open without writing is what shows it is waiting, and writing one byte is the
# keypress.
#
# No tmux server is involved, but the suite takes the tmux suites' guard
# anyway, for two reasons of its own: BSD script(1) refuses a fifo on stdin
# ("tcgetattr/ioctl: Operation not supported"), so only util-linux's can drive
# it, and the pause reads /dev/tty -- which, on a developer's machine, is the
# developer's terminal. Container or CI only, via bin/test-in-docker.

set -u
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2

DIR=$(mktemp -d)
SCRIPT="$(cd "$(dirname "$0")" && pwd)/tmux-tig"
fails=0
PID=""
cleanup() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null
  exec 3>&- 2>/dev/null
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
has() { # has <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       missing: %s\n       in:      %s\n' "$1" "$3" "$(tr -d '\r' <"$2" 2>/dev/null)"
    fails=$((fails + 1))
  fi
}
lacks() { # lacks <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then
    printf 'FAIL %s\n       present: %s\n' "$1" "$3"
    fails=$((fails + 1))
  else
    printf 'ok   %s\n' "$1"
  fi
}

# tig records its argv, prints what the real one prints outside a repository,
# and exits $TIG_EXIT.
mkdir -p "$DIR/stub"
cat >"$DIR/stub/tig" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >"$TIG_ARGS"
[ "${TIG_EXIT:-0}" -eq 0 ] || echo "tig: Not a git repository" >&2
exit "${TIG_EXIT:-0}"
STUB
chmod +x "$DIR/stub/tig"
export TIG_ARGS="$DIR/tig.args"

# util-linux script(1); TERM is set because a runner has none.
in_pty() { env TERM=xterm-256color script -qec "$*" /dev/null; }

# start <tig exit> <args...> -- run tmux-tig in a pty, input from the fifo
# held open on fd 3, output to $DIR/out. Sets PID.
start() {
  local code=$1
  shift
  rm -f "$DIR/in" "$DIR/out"
  mkfifo "$DIR/in"
  TIG_EXIT=$code PATH="$DIR/stub:$PATH" in_pty "$SCRIPT" "$@" <"$DIR/in" >"$DIR/out" 2>&1 &
  PID=$!
  exec 3>"$DIR/in"
}
# finish -- sets RC to the exit status, or "still running" after ~3s. Sets a
# variable rather than printing, because `wait` only works in the shell that
# started the job, never in a command substitution's subshell.
finish() {
  local _
  RC="still running"
  for _ in $(seq 1 30); do
    if ! kill -0 "$PID" 2>/dev/null; then
      wait "$PID"
      RC=$?
      PID=""
      return
    fi
    sleep 0.1
  done
}

# --- tig succeeds: no pause ----------------------------------------------------
start 0 --all
finish
t "success: exits without waiting for a key" "0" "$RC"
exec 3>&-
lacks "success: no pause line" "$DIR/out" "Press any key"
t "success: the arguments reach tig" "--all" "$(cat "$TIG_ARGS")"

# --- tig fails: the message stays until one key ------------------------------
start 3
sleep 1
t "failure: still open before any key is pressed" "running" \
  "$(kill -0 "$PID" 2>/dev/null && echo running || echo exited)"
has "failure: tig's own message is on screen" "$DIR/out" "tig: Not a git repository"
has "failure: the pause line names the status" "$DIR/out" "tig exited with status 3"
# One byte, no Enter: the read is -icanon, so a single keystroke closes it.
printf 'x' >&3
finish
t "failure: one key closes it, with tig's status" "3" "$RC"
exec 3>&-

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
