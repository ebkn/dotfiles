#!/usr/bin/env zsh
# Unit tests for the Wi-Fi keepalive in zsh/ssh.zsh.
#
# myssh runs a ping at ~3 packets a second for as long as a connection to that
# host lasts -- ONE ping per host, however many myssh connections share it.
# Two things can go wrong, and both are silent:
#
#   - a leak. The ping has to be disowned, or it would announce itself on every
#     connection, and a disowned job outlives the SIGHUP its shell sends on the
#     way out. Close the pane mid-session and the ping ran until reboot.
#   - a gap or a pile-up. Four panes on one host used to run four pings (~27
#     packets a second); sharing one means the ping must survive any one
#     connection ending while another is still open, and must never double up.
#
# So the contract is a lifetime and a count, not an output, and the only honest
# way to check either is to watch real processes: `ping` is stubbed (nothing may
# put packets on the wire from a test) but everything else -- the disowned
# supervisor, the lock, the poll loop, the signals -- is the real thing.
#
# _SSH_KEEPALIVE_POLL is turned right down so the tests do not wait seconds,
# _SSH_KEEPALIVE_DIR points the shared state at a scratch dir, and
# _ssh_keepalive_start takes the owner pid as an argument so a test can own a
# process it is allowed to kill -- and play several "shells" from one.
#
# Run: zsh zsh/ssh-keepalive.test.zsh   (exit 0 = pass)

set -u

source "${0:A:h}/ssh.zsh"

typeset -i failures=0

work=${$(mktemp -d):A}
stub_bin="$work/bin"
mkdir -p "$stub_bin"
_SSH_KEEPALIVE_DIR="$work/state"

# A ping that records its own pid and then does nothing until it is killed --
# the same shape as the real one from the caller's point of view. Every ping of
# a case goes to the same file, so counting live pids there counts the pings.
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

# case_file <name> -- start a fresh ping record for one case.
case_file() {
  PING_PIDFILE="$work/ping.$1"
  : > "$PING_PIDFILE"
  export PING_PIDFILE
}

# first_ping -- the first pid the stub recorded, waiting for it to appear.
first_ping() {
  local i
  for i in {1..40}; do
    [[ -s "$PING_PIDFILE" ]] && { head -1 "$PING_PIDFILE"; return }
    sleep 0.1
  done
}

# live_pings -- how many recorded pings are running, once things have settled.
# Settling is a fixed wait on purpose: the question is "did a SECOND ping
# appear", and absence cannot be polled for. Five poll intervals covers a
# candidate supervisor losing the lock race and an owner being pruned.
live_pings() {
  sleep 1
  local n=0 pid
  while IFS= read -r pid; do
    [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && (( n++ ))
  done < "$PING_PIDFILE"
  echo $n
}

# owner -- a process standing in for one shell running myssh.
owner() { sleep 600 >/dev/null 2>&1 &! echo $!; }

# --- the ordinary path: myssh stops the keepalive when the session ends -----
case_file stop
_ssh_keepalive_start 10.0.0.1
png=$(first_ping)
check 'a session starts a ping' 'alive' "$(alive "$png")"
_ssh_keepalive_stop
check 'stopping the only session stops the ping' 'gone' "$(wait_gone "$png")"
check 'stop clears the recorded owner' '' "$_SSH_KEEPALIVE_OWNER"

# --- the leak: the owning shell dies without myssh ever returning -----------
case_file owner
o1=$(owner)
_ssh_keepalive_start 10.0.0.2 "$o1"
png=$(first_ping)
check 'the ping starts for a live owner' 'alive' "$(alive "$png")"
kill "$o1"
check 'the ping stops when its shell is gone' 'gone' "$(wait_gone "$png")"
_SSH_KEEPALIVE_OWNER=""

# --- sharing: several sessions on one host run one ping ---------------------
case_file share
o1=$(owner) o2=$(owner)
_ssh_keepalive_start 10.0.0.3 "$o1"
own1=$_SSH_KEEPALIVE_OWNER
png=$(first_ping)
_ssh_keepalive_start 10.0.0.3 "$o2"
own2=$_SSH_KEEPALIVE_OWNER
check 'two sessions on one host run one ping' '1' "$(live_pings)"

# The gap: the ping must outlive any one session while another remains.
_SSH_KEEPALIVE_OWNER=$own1 _ssh_keepalive_stop
check 'the first session ending keeps the shared ping' 'alive' "$(sleep 1; alive "$png")"
_SSH_KEEPALIVE_OWNER=$own2 _ssh_keepalive_stop
check 'the last session ending stops it' 'gone' "$(wait_gone "$png")"

# A session arriving after the last one left needs a ping of its own; the
# previous supervisor released the lock on its way out.
_ssh_keepalive_start 10.0.0.3 "$o1"
check 'a later session on that host starts a new one' '1' "$(live_pings)"
_ssh_keepalive_stop
kill "$o1" "$o2"

# --- different hosts are independent ----------------------------------------
case_file hosts
o1=$(owner)
_ssh_keepalive_start 10.0.0.4 "$o1"
own1=$_SSH_KEEPALIVE_OWNER
_ssh_keepalive_start 10.0.0.5 "$o1"
own2=$_SSH_KEEPALIVE_OWNER
check 'two hosts run two pings' '2' "$(live_pings)"
_SSH_KEEPALIVE_OWNER=$own1 _ssh_keepalive_stop
_SSH_KEEPALIVE_OWNER=$own2 _ssh_keepalive_stop
kill "$o1"

# --- a stale lock: the supervisor was killed outright -----------------------
# SIGKILL runs no trap, so the lock is left naming a dead pid. Without stale
# detection every later session on that host would run with no keepalive.
case_file stale
o1=$(owner)
_ssh_keepalive_start 10.0.0.6 "$o1"
png=$(first_ping)
kill -9 "$(readlink "$_SSH_KEEPALIVE_DIR/10.0.0.6.lock")"
kill "$png"  # the orphan a SIGKILLed supervisor leaves; not what is under test
: > "$PING_PIDFILE"
o2=$(owner)
_ssh_keepalive_start 10.0.0.6 "$o2"
check 'a stale lock does not block a new ping' '1' "$(live_pings)"
_ssh_keepalive_stop
kill "$o1" "$o2"

# --- nothing to ping --------------------------------------------------------
_ssh_keepalive_start ""
check 'an unresolvable host starts nothing' '' "$_SSH_KEEPALIVE_OWNER"
_ssh_keepalive_stop
check 'and stop is a no-op then' '0' "$?"

# A failing run is by definition one that leaked a process, so clean up after
# the assertions rather than trusting them: every pid the stub ever recorded,
# and any supervisor still holding a lock.
for _lock in "$_SSH_KEEPALIVE_DIR"/*.lock(N@); do
  kill "$(readlink "$_lock")" 2>/dev/null
done
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
