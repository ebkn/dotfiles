#!/usr/bin/env bash
# Tests for bin/tmux-agent-view — the answer-it-here view behind ctrl-o in the
# prefix + a picker.
#
# Like bin/tmux-popup.test.sh, and for the same structural reason, this runs
# against a STUBBED tmux rather than a throwaway server: the script's whole job
# is display-popup plus attach, and both need an attached client with a pty,
# which `run-shell` does not have. So the assertions are on the command lines
# the script decides, which is the part it owns. That the resulting popup then
# behaves was verified by hand against a real server with a pty client (an 80x23
# window stayed 80x23 with the mirror attached, the real tab stayed on its own
# window, and detaching reopened the picker).
#
# What is worth pinning here is everything whose absence is SILENT:
#
#   * -B, `status off`, and -w/-h taken from the target window. These three are
#     what keep the mirror from resizing the window it is showing (see the
#     header of the script). Drop any one and the window loses a row or a
#     column: no error, just a transcript that reflowed for no visible reason.
#   * -C before the second display-popup. Without it tmux MODIFIES the picker's
#     popup instead of opening a new one, ignoring -w, -h and the command — so
#     ctrl-o would appear to do nothing at all.
#   * the `_*` session name, which is the guard .tmux.conf uses to refuse
#     opening a popup from inside a popup.
#   * the sweep only killing unattached mirrors. It runs kill-session against
#     names it derives from a listing; getting the filter wrong would kill a
#     session someone is using.
#   * the list geometry, which is duplicated in .tmux.conf so that detaching
#     lands you back on the same list at the same size.
#
# Run: bash bin/tmux-agent-view.test.sh   (exit 0 = pass)
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
conf="$PWD/.tmux.conf"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A copy, not a symlink: the script resolves its sibling from $0 without
# following symlinks (both live in the same directory in the checkout and in
# ~/.local/bin), and the `list` mode has to name a tmux-agents next to itself.
mkdir -p "$work/bin"
cp bin/tmux-agent-view "$work/bin/tmux-agent-view"
script="$work/bin/tmux-agent-view"

# Records every tmux invocation, one per line, and answers the two queries the
# script makes. 137x42 is deliberately not a round number and not the size of
# anything else here, so a hard-coded or percentage geometry cannot pass.
cat >"$work/tmux" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$work/calls"
case "\$1" in
  display-message)
    case "\$*" in
      *window_width*) echo "137 42" ;;
      *session_name*) echo "work" ;;
    esac
    ;;
  list-sessions)
    printf '_agent_9_1 0\n_agent_8_2 1\n_popup_0 0\nwork 1\n'
    ;;
esac
exit 0
STUB
chmod +x "$work/tmux"
mkdir -p "$work/stub"
ln -s "$work/tmux" "$work/stub/tmux"

failures=0
fail() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; do printf '  %s\n' "$l"; done; failures=$((failures + 1)); }
pass() { printf 'ok   %s\n' "$1"; }

run() {
  : >"$work/calls"
  PATH="$work/stub:$PATH" "$script" "$@" >"$work/out" 2>&1
}

# has <desc> <substring> — the recorded calls contain a line matching it.
has() {
  local desc=$1 needle=$2
  if grep -qF -- "$needle" "$work/calls"; then
    pass "$desc"
  else
    fail "$desc" "no call matching: $needle" "calls:" "$(cat "$work/calls")"
  fi
}
hasnt() {
  local desc=$1 needle=$2
  if grep -qF -- "$needle" "$work/calls"; then
    fail "$desc" "unexpected call: $(grep -F -- "$needle" "$work/calls")"
  else
    pass "$desc"
  fi
}

# --- open --------------------------------------------------------------------

run open /dev/ttys001 @7 %42

has 'the picker popup is closed before the mirror is opened' \
  'display-popup -C -c /dev/ttys001'

# The order matters as much as the presence: a -C after the fact would close the
# mirror it just opened.
close_line=$(grep -n 'display-popup -C' "$work/calls" | head -1 | cut -d: -f1)
open_line=$(grep -n 'display-popup -B' "$work/calls" | head -1 | cut -d: -f1)
if [ -n "$close_line" ] && [ -n "$open_line" ] && [ "$close_line" -lt "$open_line" ]; then
  pass 'the close comes first'
else
  fail 'the close comes first' "close at line ${close_line:-none}, open at ${open_line:-none}"
fi

has 'the mirror popup is borderless and sized to the target window' \
  'display-popup -B -c /dev/ttys001 -E -w 137 -h 42'
has 'the mirror popup runs the attach mode against the picked window and pane' \
  "$script attach /dev/ttys001 @7 %42"

# A percentage here would be the easy mistake, and it is the one that resizes
# the window the view exists to show.
# Matched on the -w/-h values alone: the pane id in the same line is a %42, so
# a bare search for "%" passes on the wrong thing.
mirror_geom=$(grep -o -- '-w [^ ]* -h [^ ]*' "$work/calls" | head -1)
case "$mirror_geom" in
  *%*) fail 'the mirror geometry is absolute, not a percentage' "got: $mirror_geom" ;;
  *) pass 'the mirror geometry is absolute, not a percentage' ;;
esac

has 'an unattached mirror session is swept'   'kill-session -t _agent_9_1'
hasnt 'an attached mirror session is spared'  'kill-session -t _agent_8_2'
hasnt 'a popup session is not swept'          'kill-session -t _popup_0'
hasnt 'a real session is never swept'         'kill-session -t work'

# --- attach ------------------------------------------------------------------

run attach /dev/ttys001 @7 %42

has 'the mirror session is grouped with the target session' \
  'new-session -d -t work -s _agent_7_'
has 'the status line is off in the mirror, or it is one row short' \
  'set-option -t _agent_7_'
has 'the mirror is pointed at the picked window' \
  'select-window -t _agent_7_'
has 'the picked pane is made active, so keys reach the agent' \
  'select-pane -t %42'
has 'the mirror is attached' 'attach-session -t _agent_7_'
has 'the mirror session is killed once it is left' 'kill-session -t _agent_7_'
has 'the picker is reopened after detaching' \
  "run-shell -b $script list /dev/ttys001"

status_call=$(grep 'set-option -t _agent_7_' "$work/calls" | head -1)
case "$status_call" in
  *"status off") pass 'the status line is turned off, not merely touched' ;;
  *) fail 'the status line is turned off, not merely touched' "got: $status_call" ;;
esac

# The cross-file half of the naming contract: .tmux.conf refuses prefix + p/t/o/a
# when #{session_name} matches _*, which is what stops a popup being opened from
# inside the mirror.
session=$(sed -n 's/.*new-session -d -t work -s \([^ ]*\).*/\1/p' "$work/calls" | head -1)
case "$session" in
  _*) pass 'the mirror session name matches the _* guard in .tmux.conf' ;;
  *) fail 'the mirror session name matches the _* guard in .tmux.conf' "got: $session" ;;
esac

# --- list --------------------------------------------------------------------

run list /dev/ttys001
has 'the picker popup is closed before it is reopened' \
  'display-popup -C -c /dev/ttys001'
has 'the picker is reopened next to this script, not via $PATH' \
  "$work/bin/tmux-agents"

# tmux run-shell uses the SERVER's environment, so a bare name would resolve
# against whatever $PATH the server was started with.
if grep -qE 'display-popup .*[^/]tmux-agents$' "$work/calls" &&
  ! grep -qF "$work/bin/tmux-agents" "$work/calls"; then
  fail 'the picker path is absolute' "$(grep tmux-agents "$work/calls")"
else
  pass 'the picker path is absolute'
fi

# The geometry is duplicated in .tmux.conf on purpose (a binding cannot read it
# from here), so the two have to be checked against each other.
conf_geom=$(sed -n 's/.*display-popup -E \(-w [0-9]*% -h [0-9]*%\) "tmux-agents".*/\1/p' "$conf" | head -1)
view_geom=$(grep -o -- '-w [0-9]*% -h [0-9]*%' "$work/calls" | head -1)
if [ -z "$conf_geom" ]; then
  fail 'the prefix + a geometry can be read out of .tmux.conf' \
    'no `display-popup -E -w N% -h N% "tmux-agents"` line found'
elif [ "$conf_geom" = "$view_geom" ]; then
  pass "the reopened list matches the prefix + a geometry ($conf_geom)"
else
  fail 'the reopened list matches the prefix + a geometry' \
    "conf: $conf_geom" "view: $view_geom"
fi

# --- argument handling --------------------------------------------------------

# A silent exit 0 here would look exactly like a working key: the popup would
# open and close again with nothing in it.
check_rc() {
  local desc=$1 want=$2
  shift 2
  PATH="$work/stub:$PATH" "$script" "$@" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq "$want" ]; then pass "$desc"; else fail "$desc" "want rc=$want, got $rc"; fi
}
check_rc 'a missing argument is a usage error' 2 open /dev/ttys001 @7
check_rc 'an unknown mode is a usage error' 2 bogus
check_rc 'no arguments at all is a usage error' 2

if [ "$failures" -ne 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
