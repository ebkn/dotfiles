#!/usr/bin/env bash
# Tests for bin/autossh-ssh, the AUTOSSH_PATH shim myssh points autossh at.
#
# Every failure here is silent by construction. The shim sits between autossh
# and ssh on a path that only runs when the network has already gone wrong, so
# a broken one is discovered during an outage, which is the worst moment to
# find out: dropping an argument breaks the reconnect itself, and a stray write
# to the terminal is exactly the mess this exists to remove.
#
# `ssh` is stubbed -- nothing here may dial out -- and the stub records the argv
# it was handed, which is the shim's real contract with autossh. The notice is
# read off the shim's own stderr: with no controlling terminal the /dev/tty
# write fails and `emit` falls back to stderr, and from attempt two onwards
# ssh's stderr goes to the log file, so stderr carries the notice alone.
#
# Run: bash bin/autossh-ssh.test.sh   (exit 0 = pass)
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
shim="$PWD/bin/autossh-ssh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; do printf '  %s\n' "$l"; done; failures=$((failures + 1)); }

# The stub is found as `ssh` on PATH, which is also the reason the shim is not
# itself named ssh: `command -v ssh` inside a shim called ssh finds the shim.
mkdir -p "$work/bin"
cat > "$work/bin/ssh" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" > "$SSH_STUB_ARGV"
[ -n "${SSH_STUB_STDERR:-}" ] && printf '%s\n' "$SSH_STUB_STDERR" >&2
exit "${SSH_STUB_EXIT:-0}"
STUB
chmod +x "$work/bin/ssh"
export PATH="$work/bin:$PATH"
export SSH_STUB_ARGV="$work/argv"

state="$work/notice"
run() { # run <stderr-file> [args...] — invoke the shim, capture its stderr
  local err=$1
  shift
  AUTOSSH_NOTICE_STATE="$state" AUTOSSH_NOTICE_HOST="thehost" \
    "$shim" "$@" 2> "$err"
}

# --- attempt 1: the initial connection is left completely alone ------------
: > "$state"
run "$work/err1" -o ControlPath=none -t thehost 'tmux attach'
argv=$(cat "$SSH_STUB_ARGV")
expected=$'-o\nControlPath=none\n-t\nthehost\ntmux attach'
if [ "$argv" = "$expected" ]; then
  pass "attempt 1: argv reaches ssh untouched"
else
  fail "attempt 1: argv reaches ssh untouched" "got:" "$argv"
fi

if [ -s "$work/err1" ]; then
  fail "attempt 1: draws nothing" "stderr was not empty:" "$(cat "$work/err1")"
else
  pass "attempt 1: draws nothing"
fi

# ssh's own diagnostics must still reach the terminal on the first attempt:
# that is where "Permission denied" and a changed host key show up.
SSH_STUB_STDERR="Permission denied (publickey)." \
  AUTOSSH_NOTICE_STATE="$work/first" AUTOSSH_NOTICE_HOST="thehost" \
  "$shim" thehost 2> "$work/err1b"
if grep -q 'Permission denied' "$work/err1b"; then
  pass "attempt 1: ssh's own stderr still reaches the terminal"
else
  fail "attempt 1: ssh's own stderr still reaches the terminal" \
    "stderr: $(cat "$work/err1b")"
fi

# --- attempt 2: the notice, and the end of the mouse flood -----------------
SSH_STUB_STDERR="ssh: connect to host thehost port 22: Operation timed out" \
  run "$work/err2" thehost
notice=$(cat "$work/err2")

if printf '%s' "$notice" | grep -q 'reconnecting to thehost'; then
  pass "attempt 2: names the host it is reconnecting to"
else
  fail "attempt 2: names the host it is reconnecting to" "stderr: $notice"
fi

if printf '%s' "$notice" | grep -q '(2)'; then
  pass "attempt 2: counts the attempt"
else
  fail "attempt 2: counts the attempt" "stderr: $notice"
fi

# The mouse reset is the fix for the flood of raw SGR reports when the pointer
# moves while nothing is consuming the remote tmux's mouse tracking. All five
# tracking modes plus bracketed paste, matching _ssh_decorate_off.
missing=""
for seq in '\[?9l' '\[?1000l' '\[?1002l' '\[?1003l' '\[?1006l' '\[?2004l'; do
  printf '%s' "$notice" | grep -q "$seq" || missing="$missing $seq"
done
if [ -z "$missing" ]; then
  pass "attempt 2: turns mouse tracking and bracketed paste off"
else
  fail "attempt 2: turns mouse tracking and bracketed paste off" "missing:$missing"
fi

if printf '%s' "$notice" | grep -q '\[2J'; then
  pass "attempt 2: clears the stale remote frame"
else
  fail "attempt 2: clears the stale remote frame" "no clear-screen in the notice"
fi

# --- attempt 3: quotes ssh's last words, and stops re-clearing -------------
SSH_STUB_STDERR="ssh: connect to host thehost port 22: Operation timed out" \
  run "$work/err3" thehost
notice3=$(cat "$work/err3")

if printf '%s' "$notice3" | grep -q 'Operation timed out'; then
  pass "attempt 3: shows what ssh said on the previous attempt"
else
  fail "attempt 3: shows what ssh said on the previous attempt" "stderr: $notice3"
fi

# ssh retries about once a second; clearing the screen every time would flicker
# it continuously, so only the first notice of an outage clears.
if printf '%s' "$notice3" | grep -q '\[2J'; then
  fail "attempt 3: repaints without clearing the screen again" \
    "the notice cleared the screen on a later attempt"
else
  pass "attempt 3: repaints without clearing the screen again"
fi

if grep -q 'Operation timed out' "$state.log"; then
  pass "attempt 3: ssh's stderr is kept in the log, not on the screen"
else
  fail "attempt 3: ssh's stderr is kept in the log, not on the screen" \
    "log: $(cat "$state.log" 2>/dev/null)"
fi

# --- no state file: a transparent exec ------------------------------------
# This is the shape on a machine where the shim is deployed but the caller is
# not myssh, and the one that must not surprise anybody.
env -u AUTOSSH_NOTICE_STATE SSH_STUB_STDERR="plain" "$shim" thehost 2> "$work/err4"
if [ "$(cat "$SSH_STUB_ARGV")" = "thehost" ] && grep -q 'plain' "$work/err4"; then
  pass "without AUTOSSH_NOTICE_STATE: a transparent exec of ssh"
else
  fail "without AUTOSSH_NOTICE_STATE: a transparent exec of ssh" \
    "argv: $(cat "$SSH_STUB_ARGV")" "stderr: $(cat "$work/err4")"
fi

# --- ssh's exit status is autossh's restart policy ------------------------
# The shim must be invisible here: autossh decides whether to retry from this
# number, so swallowing or rewriting it would change the reconnect behaviour.
SSH_STUB_EXIT=255 run "$work/err5" thehost
ret=$?
if [ "$ret" = "255" ]; then
  pass "ssh's exit status passes through"
else
  fail "ssh's exit status passes through" "got $ret, want 255"
fi

if [ "$failures" -gt 0 ]; then
  printf '\n%d failure(s)\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
