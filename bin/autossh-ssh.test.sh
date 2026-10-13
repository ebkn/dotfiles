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
# it was handed, which is the shim's real contract with autossh.
#
# The notice is drawn on AUTOSSH_NOTICE_TTY, pointed here at a plain file, so
# the frame can be read back whole and the suite never touches the terminal it
# is run from. It used to rely on there being no controlling terminal at all:
# from an interactive shell it failed five cases and left the terminal cleared
# with its cursor hidden. A plain file also has no size, so the shim falls back
# to 24x80 and every column below is fixed.
#
# Run: bash bin/autossh-ssh.test.sh   (exit 0 = pass)
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
shim="$PWD/bin/autossh-ssh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  shift
  for l in "$@"; do printf '  %s\n' "$l"; done
  failures=$((failures + 1))
}
same() { # same <label> <want> <got>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want: $2" "got:  $3"; fi
}

# The stub is found as `ssh` on PATH, which is also the reason the shim is not
# itself named ssh: `command -v ssh` inside a shim called ssh finds the shim.
mkdir -p "$work/bin"
cat >"$work/bin/ssh" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" > "$SSH_STUB_ARGV"
printf 'remote session\n'
[ -n "${SSH_STUB_STDERR:-}" ] && printf '%s\n' "$SSH_STUB_STDERR" >&2
exit "${SSH_STUB_EXIT:-0}"
STUB
chmod +x "$work/bin/ssh"
export PATH="$work/bin:$PATH"
export SSH_STUB_ARGV="$work/argv"

state="$work/notice"
tty="$work/tty"
E=$(printf '\033')
ARGS=(-o ControlPath=none -t thehost 'tmux attach')
ARGV_WANT=$'-o\nControlPath=none\n-t\nthehost\ntmux attach'

# attempt <n> <stderr-file> [ssh-stderr] -- run the shim as attempt <n>. The
# counter is seeded, not inherited from the case before, so each case says
# which attempt it is about. stdout goes to $work/out: it is the remote
# session itself, so it must carry ssh's output and nothing of the notice.
attempt() {
  local n=$1 err=$2
  printf '%s' "$((n - 1))" >"$state"
  : >"$tty"
  SSH_STUB_STDERR="${3:-}" AUTOSSH_NOTICE_STATE="$state" AUTOSSH_NOTICE_HOST="thehost" \
    AUTOSSH_NOTICE_TTY="$tty" "$shim" "${ARGS[@]}" >"$work/out" 2>"$err"
}
stdout_is_ssh() { same "attempt $1: stdout is ssh's alone" "remote session" "$(cat "$work/out")"; }
# The frame with every CSI sequence removed: the text a person would see.
visible() { sed "s/${E}\[[0-9;?]*[A-Za-z]//g" "$1"; }

# --- attempt 1: the initial connection is left completely alone ------------
/bin/rm -f "$state.log"
attempt 1 "$work/err1" "Permission denied (publickey)."
same "attempt 1: argv reaches ssh untouched" "$ARGV_WANT" "$(cat "$SSH_STUB_ARGV")"
same "attempt 1: draws nothing" "" "$(cat "$tty")"
stdout_is_ssh 1
# ssh's own diagnostics must still reach the terminal on the first attempt:
# that is where "Permission denied" and a changed host key show up.
same "attempt 1: ssh's own stderr still reaches the terminal" \
  "Permission denied (publickey)." "$(cat "$work/err1")"

# --- attempt 2: the notice, and the end of the mouse flood -----------------
/bin/rm -f "$state.log"
attempt 2 "$work/err2" "msg-of-attempt-2"
same "attempt 2: argv reaches ssh untouched" "$ARGV_WANT" "$(cat "$SSH_STUB_ARGV")"
# Whole, not contains: a stray "Device not configured" from a redirection, or
# any other byte, in front of the notice is the mess this shim removes.
same "attempt 2: the screen shows the notice and nothing else" \
  "reconnecting to thehost … (2)" "$(visible "$tty")"
same "attempt 2: nothing reaches stderr" "" "$(cat "$work/err2")"
stdout_is_ssh 2
# The mouse reset is the fix for the flood of raw SGR reports when the pointer
# moves while nothing is consuming the remote tmux's mouse tracking. All five
# tracking modes plus bracketed paste, matching _ssh_decorate_off, then a clear.
reset="${E}[?9l${E}[?1000l${E}[?1002l${E}[?1003l${E}[?1006l${E}[?2004l${E}[0m${E}[2J${E}[?25l"
case "$(cat "$tty")" in
  "$reset${E}[12;"*) pass "attempt 2: resets mouse and paste, clears, then draws mid-screen" ;;
  *) fail "attempt 2: resets mouse and paste, clears, then draws mid-screen" "frame: $(cat -v "$tty")" ;;
esac
# From attempt two on, ssh's stderr is kept for the next notice, off the screen.
same "attempt 2: ssh's stderr goes to the log" "msg-of-attempt-2" "$(cat "$state.log")"

# --- attempt 3: quotes the PREVIOUS attempt, and stops re-clearing ---------
attempt 3 "$work/err3" "msg-of-attempt-3"
same "attempt 3: argv reaches ssh untouched" "$ARGV_WANT" "$(cat "$SSH_STUB_ARGV")"
# Different messages per attempt, so "the previous one" and "this one" can be
# told apart: the screen must quote attempt 2, and attempt 3's own words must
# be in the log rather than anywhere visible.
same "attempt 3: shows what ssh said on the previous attempt" \
  "reconnecting to thehost … (3)msg-of-attempt-2" "$(visible "$tty")"
same "attempt 3: its own stderr is in the log" "msg-of-attempt-3" "$(cat "$state.log")"
same "attempt 3: and not on stderr" "" "$(cat "$work/err3")"
stdout_is_ssh 3
# ssh retries about once a second; clearing the screen every time would flicker
# it continuously, so only the first notice of an outage clears.
case "$(cat "$tty")" in
  *"${E}[2J"*) fail "attempt 3: repaints without clearing the screen again" "frame: $(cat -v "$tty")" ;;
  *) pass "attempt 3: repaints without clearing the screen again" ;;
esac
# The quoted line is centred on its own width. Its dim/reset escapes used to be
# counted as text, putting it four columns left of the line above.
# "msg-of-attempt-2" is 16 wide: (80 - 16) / 2 + 1 = 33.
case "$(cat "$tty")" in
  *"${E}[14;33H${E}[2mmsg-of-attempt-2${E}[0m") pass "attempt 3: the quoted line is centred on its visible width" ;;
  *) fail "attempt 3: the quoted line is centred on its visible width" "frame: $(cat -v "$tty")" ;;
esac

# --- a multi-line diagnostic: the LAST non-blank line is the one quoted -----
# ssh's fatal messages are several lines, and the useful one comes last: a
# changed host key prints a banner of @-lines first. A one-line log cannot tell
# `tail -1` from `head -1`, nor a trailing blank line from content.
printf '@@@@@@@@@@@@@@@@@@@@@@@@\n@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @\nHost key verification failed.\n\n   \n' \
  >"$state.log"
attempt 3 "$work/err-multi"
same "a multi-line log: the last non-blank line is quoted" \
  "reconnecting to thehost … (3)Host key verification failed." "$(visible "$tty")"

# --- no terminal to draw on: the notice falls back to stderr ---------------
# autossh started outside a terminal (a launchd job, say) has no /dev/tty, and
# the write must not then vanish or print an error in its place.
printf '1' >"$state"
/bin/rm -f "$state.log"
SSH_STUB_STDERR="" AUTOSSH_NOTICE_STATE="$state" AUTOSSH_NOTICE_HOST="thehost" \
  AUTOSSH_NOTICE_TTY="$work/no-such-dir/tty" "$shim" thehost >/dev/null 2>"$work/err-notty"
same "with no terminal, the notice goes to stderr instead" \
  "reconnecting to thehost … (2)" "$(visible "$work/err-notty")"

# --- the counter itself -----------------------------------------------------
# A state file left half-written must not be read as some later attempt: it
# restarts at 1, which is the transparent exec.
printf 'garbage' >"$state"
: >"$tty"
AUTOSSH_NOTICE_STATE="$state" AUTOSSH_NOTICE_TTY="$tty" "$shim" thehost >/dev/null 2>&1
same "a garbage counter restarts at attempt 1" "1" "$(cat "$state")"
same "which draws nothing" "" "$(cat "$tty")"

# --- no state file: a transparent exec ------------------------------------
# This is the shape on a machine where the shim is deployed but the caller is
# not myssh, and the one that must not surprise anybody.
: >"$tty"
env -u AUTOSSH_NOTICE_STATE SSH_STUB_STDERR="plain" AUTOSSH_NOTICE_TTY="$tty" \
  "$shim" thehost >/dev/null 2>"$work/err4"
same "without AUTOSSH_NOTICE_STATE: argv untouched" "thehost" "$(cat "$SSH_STUB_ARGV")"
same "and ssh's stderr is its own" "plain" "$(cat "$work/err4")"
same "and nothing is drawn" "" "$(cat "$tty")"

# --- ssh's exit status is autossh's restart policy ------------------------
# The shim must be invisible here: autossh decides whether to retry from this
# number, so swallowing or rewriting it would change the reconnect behaviour.
# Checked on a reconnect attempt, where the shim has done the most before exec.
SSH_STUB_EXIT=255 attempt 3 "$work/err5"
same "ssh's exit status passes through" "255" "$?"

if [ "$failures" -gt 0 ]; then
  printf '\n%d failure(s)\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
