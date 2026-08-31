#!/usr/bin/env zsh
# Unit tests for the Wi-Fi keepalive in zsh/ssh.zsh.
#
# myssh runs a ping at ~3 packets a second for as long as the connection lasts.
# It has to be disowned, or it would announce itself on every connection -- and
# that is exactly what made it leak: a disowned job outlives the SIGHUP its
# shell sends on the way out, and myssh's own kill is only reached when myssh
# returns. Close the pane mid-session and the ping ran until the machine was
# rebooted.
#
# So the contract here is a lifetime, not an output, and the only honest way to
# check a lifetime is to watch real processes: `ping` is stubbed (nothing may
# put packets on the wire from a test) but everything else -- the disowned
# supervisor, the poll loop, the signals -- is the real thing.
#
# _SSH_KEEPALIVE_POLL is turned right down so the tests do not wait seconds,
# and _ssh_keepalive_start takes the owner pid as an argument so a test can own
# a process it is allowed to kill.
#
# Run: zsh zsh/ssh-keepalive.test.zsh   (exit 0 = pass)

set -u

source "${0:A:h}/ssh.zsh"

typeset -i failures=0

work=${$(mktemp -d):A}
stub_bin="$work/bin"
mkdir -p "$stub_bin"

# A ping that records its own pid and then does nothing until it is killed --
# the same shape as the real one from the caller's point of view.
cat >"$stub_bin/ping" <<'STUB'
#!/bin/sh
echo $$ >> "$PING_PIDFILE"
exec sleep 600
STUB
chmod +x "$stub_bin/ping"

PATH="$stub_bin:$PATH"
rehash
_SSH_KEEPALIVE_POLL=0.2

check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

alive() { kill -0 "$1" 2>/dev/null && echo alive || echo gone; }

# wait_gone <pid> -- poll for up to ~4s. A plain sleep would either be flaky or
# slow; this reports as soon as the process is reaped and only pays the full
# wait when the answer is genuinely "still alive", i.e. when the test fails.
wait_gone() {
  local pid=$1 i
  for i in {1..40}; do
    kill -0 "$pid" 2>/dev/null || { echo gone; return }
    sleep 0.1
  done
  echo alive
}

# ping_pid -- the pid the stub recorded, waiting for it to appear.
ping_pid() {
  local i
  for i in {1..40}; do
    [[ -s "$PING_PIDFILE" ]] && { head -1 "$PING_PIDFILE"; return }
    sleep 0.1
  done
}

start() {
  PING_PIDFILE="$work/ping.$1"
  : > "$PING_PIDFILE"
  export PING_PIDFILE
  _ssh_keepalive_start "$2" "${3:-$$}"
}

# --- the ordinary path: myssh stops the keepalive when the session ends -----
start stop 10.0.0.1
sup=$_SSH_KEEPALIVE_PID
png=$(ping_pid)
check 'the supervisor is running' 'alive' "$(alive "$sup")"
check 'and so is the ping' 'alive' "$(alive "$png")"
_ssh_keepalive_stop
check 'stop kills the supervisor' 'gone' "$(wait_gone "$sup")"
# The one that regressed: killing the supervisor is pointless if its child
# survives it, and an orphaned ping has nothing left that would ever stop it.
check 'and takes the ping with it' 'gone' "$(wait_gone "$png")"
check 'stop clears the recorded pid' '' "$_SSH_KEEPALIVE_PID"

# --- the leak: the owning shell dies without myssh ever returning -----------
sleep 600 &
owner=$!
start owner 10.0.0.2 "$owner"
sup=$_SSH_KEEPALIVE_PID
png=$(ping_pid)
check 'the ping starts for a live owner' 'alive' "$(alive "$png")"
kill "$owner" 2>/dev/null
check 'the ping stops when its shell is gone' 'gone' "$(wait_gone "$png")"
check 'and the supervisor does not linger either' 'gone' "$(wait_gone "$sup")"
_SSH_KEEPALIVE_PID=""

# --- nothing to ping --------------------------------------------------------
_ssh_keepalive_start ""
check 'an unresolvable host starts nothing' '' "$_SSH_KEEPALIVE_PID"
_ssh_keepalive_stop
check 'and stop is a no-op then' '0' "$?"

# A failing run is by definition one that leaked a process, so clean up after
# the assertions rather than trusting them: every pid the stub ever recorded.
for _pidfile in "$work"/ping.*; do
  [[ -s "$_pidfile" ]] || continue
  while IFS= read -r _pid; do kill "$_pid" 2>/dev/null; done < "$_pidfile"
done
/bin/rm -rf "$work"

if (( failures )); then
  printf '\nFAIL=%d\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
