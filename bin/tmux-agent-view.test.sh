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
#   * -B, and -w/-h taken from the target window with one row added for the
#     footer. That arithmetic is what keeps the mirror from resizing the window
#     it is showing (see the header of the script). Get it wrong and the window
#     loses a row or a column: no error, just a transcript that reflowed for no
#     visible reason.
#   * the footer itself — the status line naming C-q d. Sized to the window and
#     borderless, the mirror looks exactly like the tab it mirrors, so the only
#     thing saying you are in a view, and how to leave it, is that one row.
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

# 42 is the window height the stub reports; the popup gets 43, because the
# footer status line occupies a row of the popup that is not part of the window.
# Passing 42 here would take that row out of the window instead, shrinking it.
has 'the mirror popup is borderless, as wide as the window and one row taller' \
  'display-popup -B -c /dev/ttys001 -E -w 137 -h 43'
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
# The session name carries a pid, so these have to match around it.
hasre() {
  local desc=$1 pattern=$2
  if grep -qE -- "$pattern" "$work/calls"; then
    pass "$desc"
  else
    fail "$desc" "no call matching: $pattern" "calls:" "$(cat "$work/calls")"
  fi
}
hasre 'the footer status line is turned on in the mirror' \
  'set-option -t _agent_7_[0-9]+ status on'
# The global is `top` (.tmux.conf), so without this the footer lands above the
# pane, where it reads as a title rather than as the way out.
hasre 'the footer is pinned to the bottom, against the global position' \
  'set-option -t _agent_7_[0-9]+ status-position bottom'
has 'the mirror is pointed at the picked window' \
  'select-window -t _agent_7_'
has 'the picked pane is made active, so keys reach the agent' \
  'select-pane -t %42'
has 'the mirror is attached' 'attach-session -t _agent_7_'
has 'the mirror session is killed once it is left' 'kill-session -t _agent_7_'
has 'the picker is reopened after detaching' \
  "run-shell -b $script list /dev/ttys001"

# The footer is the only thing telling you that you are in a view and how to get
# out of it -- the mirror is otherwise indistinguishable from the tab it shows.
# So the key it names is asserted, not just the fact that a format was set.
footer=$(grep 'status-format' "$work/calls" | head -1)
case "$footer" in
  *"C-q d"*) pass 'the footer names the key that leaves the view' ;;
  *) fail 'the footer names the key that leaves the view' "got: ${footer:-<no status-format call>}" ;;
esac
case "$footer" in
  *align=centre*) pass 'the footer is centred' ;;
  *) fail 'the footer is centred' "got: $footer" ;;
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
has 'the picker is reopened next to this script, not through the search path' \
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
    'no display-popup line for tmux-agents found'
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
