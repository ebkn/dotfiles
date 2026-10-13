#!/bin/bash
#
# notify-send.test.sh
#
# Pins bin/wsl/notify-send, the libnotify stand-in that turns a notification
# into OSC 9 for WezTerm. Its failures are silent by design -- every write ends
# in `|| true`, because a notification must never break the command that raised
# it -- so a wrong byte means no notification and nothing said anywhere.
#
# Two halves: the argument parsing, where a value-taking flag that forgot its
# value would make that value the SUMMARY; and the bytes, where inside tmux an
# ESC that is not doubled gets the whole sequence swallowed instead of passed
# through to the terminal.
#
# NOTIFY_SEND_TTY points the write at a plain file, so nothing reaches the
# terminal the suite runs in. Runs anywhere: nothing here needs WSL.
#
# Written for bash 3.2 (/bin/bash on macOS).
set -uo pipefail

NS="$(cd "$(dirname "$0")" && pwd -P)/notify-send"
TMP=$(mktemp -d)
trap '/bin/rm -rf "$TMP"' EXIT

fails=0
t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

tty="$TMP/tty"
# ns <args...> -- run outside tmux; leaves the bytes in $tty, stderr in $TMP/err.
ns() {
  : >"$tty"
  env -u TMUX NOTIFY_SEND_TTY="$tty" "$NS" "$@" 2>"$TMP/err"
}
# osc9 <msg> -- the bytes WezTerm acts on, spelt out rather than rebuilt.
osc9() { printf '\033]9;%s\007' "$1"; }
written() { cat "$tty"; }

# --- what is written ------------------------------------------------------------
ns "Build done"
t "a summary alone exits 0" "0" "$?"
t "a summary alone is the message" "$(osc9 'Build done')" "$(written)"
ns "Build done" "in 3m"
t "a body is joined to the summary" "$(osc9 'Build done: in 3m')" "$(written)"
ns "one" "two" "three"
t "a third positional is ignored" "$(osc9 'one: two')" "$(written)"
t "and nothing reaches stderr" "" "$(cat "$TMP/err")"

# --- flags: their values must not become the message ----------------------------
# zsh-auto-notify passes urgency and an icon; libnotify's own flags take a
# separate value, and that value is not the summary.
# One flag per case, the positionals straight after it: with several flags in a
# row, one that ate a word too many ate the next FLAG and the result was the
# same. The lists are libnotify's own (tools/notify-send.c), -A and -n included.
for f in -u --urgency -t --expire-time -i --icon -a --app-name -c --category \
  -h --hint -r --replace-id -A --action -n --app-icon; do
  ns "$f" VALUE "Summary" "Body"
  t "$f skips its value" "$(osc9 'Summary: Body')" "$(written)"
done
for f in --urgency=low --expire-time=5000 --icon=terminal --app-name=zsh --category=im \
  --hint=int:x:1 --replace-id=7 --action=open --app-icon=terminal; do
  ns "$f" "Summary" "Body"
  t "$f takes nothing after it" "$(osc9 'Summary: Body')" "$(written)"
done
for f in -p --print-id -w --wait -e --transient --unknown-flag; do
  ns "$f" "Summary" "Body"
  t "$f takes nothing after it" "$(osc9 'Summary: Body')" "$(written)"
done
# The shape zsh-auto-notify actually sends: positionals first, flags after.
ns "Summary" "Body" --app-name=zsh --hint=int:transient:1 --urgency=normal --expire-time=8000
t "positionals before the flags, as zsh-auto-notify sends them" "$(osc9 'Summary: Body')" "$(written)"
ns -- "-starts with a dash" "body"
t "after --, a dash-led argument is the summary" "$(osc9 '-starts with a dash: body')" "$(written)"

# --- nothing to say ---------------------------------------------------------------
ns -u low
t "no summary exits 0" "0" "$?"
t "and writes nothing" "" "$(written)"
ns -u
t "a value-taking flag at the end exits 0" "0" "$?"
t "and writes nothing" "" "$(written)"

# --- inside tmux: one passthrough wrapper, every ESC doubled ---------------------
# tmux strips the wrapper and halves the ESCs; anything else and it eats the
# sequence. `ESC \` ends the wrapper (\134 is the backslash).
: >"$tty"
TMUX=/tmp/fake,1,0 NOTIFY_SEND_TTY="$tty" "$NS" "Summary" "Body" 2>/dev/null
t "inside tmux the sequence is wrapped once, its ESC doubled" \
  "$(printf '\033Ptmux;\033\033]9;Summary: Body\007\033\134')" "$(written)"

# --- a terminal that cannot be written ------------------------------------------
# No controlling terminal is ordinary (a cron job, a detached shell); the
# notification is lost, and nothing else may be: no error, no non-zero exit.
env -u TMUX NOTIFY_SEND_TTY="$TMP/no-such-dir/tty" "$NS" "Summary" 2>"$TMP/err"
t "an unwritable terminal still exits 0" "0" "$?"
t "and prints nothing" "" "$(cat "$TMP/err")"
TMUX=/tmp/fake,1,0 NOTIFY_SEND_TTY="$TMP/no-such-dir/tty" "$NS" "Summary" 2>"$TMP/err"
t "inside tmux too: exits 0" "0" "$?"
t "and prints nothing" "" "$(cat "$TMP/err")"

if [ "$fails" -gt 0 ]; then
  printf '\n%d failure(s)\n' "$fails"
  exit 1
fi
printf '\nPASS\n'
