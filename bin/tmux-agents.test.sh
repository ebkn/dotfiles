#!/usr/bin/env bash
# Tests for bin/tmux-agents — the prefix + a picker.
#
# The script is two halves: collect pane options from tmux, then rank and render
# them. The second half is what has logic worth pinning, and every mistake in it
# is quiet — the popup still opens and still shows a list, just the wrong one:
#
#   * rank order. Sessions blocked on a human must come first; that is the whole
#     reason the list is sorted rather than left in tmux's order. Get it wrong
#     and the one waiting for you is below the fold.
#   * the age sort inside a rank, which is what floats the longest-untouched
#     session to the top.
#   * excluding `_*` sessions, i.e. the popups this repo opens. Without it the
#     picker lists itself.
#   * the glyphs and their spacing. Each emoji glyph is two cells and the narrow
#     ▶ is padded to two, so the columns after it line up. agent-state.sh has to
#     agree with this, and nothing enforces that but a test on each side.
#
# No seam is added to the script for this. It reads panes from a real tmux
# server, which a throwaway one provides, and it hands the finished list to fzf
# on stdin — so a stub `fzf` that copies stdin out and exits non-zero captures
# exactly what the user would have seen, and makes the script exit before the
# jump. Nothing is stubbed that the script actually owns.
#
# Requires tmux; fails rather than skips without it.
#
# Run: bash bin/tmux-agents.test.sh   (exit 0 = pass)
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux-agents.test: tmux is required" >&2
  exit 1
fi

socket="agents-test-$$"
work=$(mktemp -d)
cleanup() { tmux -L "$socket" kill-server 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

failures=0
fail() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; do printf '  %s\n' "$l"; done; failures=$((failures + 1)); }
pass() { printf 'ok   %s\n' "$1"; }

mkdir -p "$work/stub"
# Stands in for the picker. Copies the rendered list out and exits 1, which is
# the same thing fzf does when the user presses Escape -- so tmux-agents takes
# its `|| exit 0` path and never reaches the jump.
cat >"$work/stub/fzf" <<STUB
#!/bin/sh
cat >"$work/list"
exit 1
STUB
chmod +x "$work/stub/fzf"

now=$(date +%s)

# Every pane runs `sleep`, never a shell. The shell these dotfiles install
# renames the window from its precmd hook (zsh/directory.zsh -> tmux-pane-titles),
# and this test identifies rows BY window name -- so a real shell renames the
# fixtures out from under the assertions a few hundred milliseconds in, which
# shows up as an intermittent failure that looks like a ranking bug.
IDLE="sleep 300"
tmux -L "$socket" -f /dev/null new-session -d -s work "$IDLE"

# One pane per state. @claude_since is set relative to now so the age column and
# the oldest-first sort within a rank are both exercised.
#   name          state     age
add_pane() {
  local name=$1 state=$2 age=$3 note=${4:-}
  tmux -L "$socket" new-window -t work -n "$name" "$IDLE"
  local pane
  pane=$(tmux -L "$socket" list-panes -t "work:$name" -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$pane" @claude_state "$state"
  tmux -L "$socket" set-option -p -t "$pane" @claude_since "$((now - age))"
  [ -n "$note" ] && tmux -L "$socket" set-option -p -t "$pane" @claude_note "$note"
}

add_pane busy-new    busy      10
add_pane stalled-old stalled   7200
add_pane asking-new  asking    30  "which one?"
add_pane waiting-old waiting   600 "needs permission"
# 400000s renders as "111h", four characters. That width is deliberate: the age
# is printed with %4s, so for the usual three-character age ("10s", "2h") the
# right-alignment contributes a leading space that exactly replaces the ▶
# glyph's own padding -- and the glyph assertion below would pass even with the
# padding removed. Only a four-character age makes the padding observable.
add_pane busy-old    busy      400000

# A pane with no agent at all must not appear.
tmux -L "$socket" new-window -t work -n plain-pane "$IDLE"

# A popup session, named the way bin/tmux-popup names them, carrying state. The
# picker must skip it.
tmux -L "$socket" new-session -d -s _popup_0 "$IDLE"
popup_pane=$(tmux -L "$socket" list-panes -t _popup_0 -F '#{pane_id}' | head -1)
tmux -L "$socket" set-option -p -t "$popup_pane" @claude_state busy
tmux -L "$socket" set-option -p -t "$popup_pane" @claude_since "$now"

run_picker() {
  rm -f "$work/list"
  tmux -L "$socket" run-shell "cd $PWD && PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/out 2>&1"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$work/list" ] && return 0
    sleep 0.2
  done
  return 1
}

if ! run_picker; then
  fail "picker produces a list" "fzf stub was never reached; output: $(cat "$work/out" 2>/dev/null)"
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi

# Column 2 onwards is what fzf displays; column 1 is the hidden jump key.
# Within the displayed part the fields are: 1 glyph, 2 age, 3 host-or-local,
# 4 window name, 5.. the note.
displayed=$(cut -f2- "$work/list")
window_order=$(awk '{ print $4 }' <<<"$displayed")

# row_for <window name> — the displayed part of that window's row, verbatim.
# Kept unsplit because the glyph's trailing padding is significant and awk
# field splitting would eat it.
row_for() { grep -F "$1" "$work/list" | head -1 | cut -f2-; }

# --- what is listed ----------------------------------------------------------

check_absent() {
  local desc=$1 needle=$2
  if grep -q "$needle" "$work/list"; then
    fail "$desc" "found: $(grep "$needle" "$work/list")"
  else
    pass "$desc"
  fi
}
check_absent "a pane with no agent is not listed" 'plain-pane'
check_absent "a _popup_ session is not listed" '_popup_'

listed=$(wc -l <"$work/list" | tr -d ' ')
if [ "$listed" -eq 5 ]; then
  pass "lists exactly the five panes that have state"
else
  fail "lists exactly the five panes that have state" "got $listed" "$(cat "$work/list")"
fi

# --- ranking -----------------------------------------------------------------

# asking and waiting share the top rank; within it the older one comes first.
# Then busy, oldest first; then everything else.
expected_order='waiting-old
asking-new
busy-old
busy-new
stalled-old'
if [ "$window_order" = "$expected_order" ]; then
  pass "blocked first, then busy, oldest first inside each rank"
else
  fail "blocked first, then busy, oldest first inside each rank" \
    "want: $(tr '\n' ' ' <<<"$expected_order")" \
    "got : $(tr '\n' ' ' <<<"$window_order")"
fi

# --- rendering ---------------------------------------------------------------

# The row must START with the glyph and its separator, so the assertion is a
# prefix match on the raw string. The separator width differs per glyph on
# purpose: the emoji ones already occupy two cells and get one space, the narrow
# ▶ is padded to two and so shows two. Anything that normalises them here would
# stop testing the thing that keeps the columns aligned.
check_glyph() {
  local desc=$1 window=$2 want=$3 row
  row=$(row_for "$window")
  case "$row" in
    "$want"*) pass "$desc" ;;
    *) fail "$desc" "row does not start with [$want]" "row: $row" ;;
  esac
}
check_glyph "asking renders as the orange diamond plus one space" asking-new  '🔶 '
check_glyph "waiting renders as the stop sign plus one space"     waiting-old '🛑 '
check_glyph "stalled renders as the grey circle plus one space"   stalled-old '🔘 '
# Checked on the row with the four-character age, for the reason given where
# busy-old is created: a shorter age hides a missing pad behind %4s.
check_glyph "busy renders as ▶ padded out to the same two cells"  busy-old    '▶  '

# Ages are rendered in the largest unit that fits, so the column stays narrow.
check_age() {
  local desc=$1 window=$2 want=$3 got
  got=$(row_for "$window" | awk '{ print $2 }')
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc" "want $want got $got"; fi
}
# The seconds case is a range, not a value. @claude_since is fixed against the
# $now captured at the top of this file, but the script calls date(1) again when
# it renders -- and the wall clock advances by a second or two while the
# fixtures are being built. The minute and hour cases are immune because their
# fixtures sit far from a unit boundary, so a few seconds of drift cannot change
# what they print; a ten-second age changes on every tick.
secs=$(row_for busy-new | awk '{ print $2 }')
case "$secs" in
  1[0-9]s) pass "an age under a minute is shown in seconds ($secs)" ;;
  *) fail "an age under a minute is shown in seconds" "want 1Xs, got $secs" ;;
esac
check_age "an age under an hour is shown in minutes"  waiting-old '10m'
check_age "an age over an hour is shown in hours"     stalled-old '2h'
check_age "an age of many hours is not abbreviated"   busy-old    '111h'

# The note is the last column and is what tells you why a session is blocked.
if grep -q 'needs permission' "$work/list" && grep -q 'which one?' "$work/list"; then
  pass "the pending note is carried into the row"
else
  fail "the pending note is carried into the row" "$(cat "$work/list")"
fi

# A local pane reports "local" rather than a host, which keeps local and remote
# rows the same shape.
if [ "$(awk '{ print $3 }' <<<"$displayed" | sort -u)" = "local" ]; then
  pass "local panes are labelled local"
else
  fail "local panes are labelled local" "$(awk '{ print $3 }' <<<"$displayed" | sort -u)"
fi

# --- remote hosts -------------------------------------------------------------

# The remote path had no coverage while it was an awk pass over a second pane
# listing. It is now a shell loop over the rows already in hand, and its failure
# is the quiet kind: remote agents simply stop appearing, on a machine where you
# rarely have a remote pane open to notice.
#
# Two things are asserted that the local cases cannot reach. The host is carried
# into the row by the *remote* tmux, through the format string this script hands
# it -- there is no longer a local sed adding the column -- so the stub derives
# the prefix from the -F argument it was given rather than hard-coding it; get
# the format wrong and the host column comes out empty and the row reads
# "local". And a host is queried once however many panes are connected to it,
# which is the dedup the `case` in that loop exists for.
cat >"$work/stub/ssh" <<STUB
#!/bin/sh
# Stands in for the remote tmux. The last argument is the remote command; the
# text between "-F '" and the first #{ is the host column this script asked the
# far end to prefix, which is exactly what is under test here.
for a in "\$@"; do cmd=\$a; done
echo "\$cmd" >>"$work/ssh-calls"
fmt=\${cmd#*-F \'}
prefix=\${fmt%%#\{*}
printf '%s%s\t@9\t%%9\tremote-win\tasking\t%s\tremote note\n' "\$prefix" remote-sess $((now - 900))
STUB
chmod +x "$work/stub/ssh"

# Two panes on the same host, so the dedup has something to collapse.
: >"$work/ssh-calls"
for w in ssh-pane-a ssh-pane-b; do
  tmux -L "$socket" new-window -t work -n "$w" "$IDLE"
  p=$(tmux -L "$socket" list-panes -t "work:$w" -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$p" @ssh_my_machine 1
  tmux -L "$socket" set-option -p -t "$p" @ssh_host bakery
done

if run_picker; then
  remote_row=$(cut -f2- "$work/list" | grep 'remote-win' || true)
  case "$remote_row" in
    *bakery*) pass "a remote agent is listed against its host, not as local" ;;
    *) fail "a remote agent is listed against its host, not as local" "row: ${remote_row:-<missing>}" ;;
  esac

  case "$remote_row" in
    *"remote note"*) pass "the remote row keeps every column, note included" ;;
    *) fail "the remote row keeps every column, note included" "row: ${remote_row:-<missing>}" ;;
  esac

  calls=$(wc -l <"$work/ssh-calls" | tr -d ' ')
  if [ "$calls" = 1 ]; then
    pass "two panes on one host are queried once, not twice"
  else
    fail "two panes on one host are queried once, not twice" "ssh ran $calls time(s)"
  fi
else
  fail "the remote path produces a list" "fzf stub was never reached"
fi

# Back to a local-only fixture so the empty case below starts from a known state.
tmux -L "$socket" kill-window -t work:ssh-pane-a 2>/dev/null
tmux -L "$socket" kill-window -t work:ssh-pane-b 2>/dev/null
rm -f "$work/stub/ssh"

# --- what the picked row turns into -------------------------------------------

# fzf runs with --expect=ctrl-o, which prints the key that closed the picker on
# its own first line -- EMPTY for a plain enter. Everything after that line is
# the row, and the hidden first field of the row is the jump key. Misread that
# by one line and the jump silently targets nothing: the popup closes and the
# tab does not change, which looks like tmux having ignored the key.
#
# The observable end of the jump is `select-pane`, so the fixture puts the agent
# in a window's SECOND pane -- if the row were misparsed, the active pane would
# stay where tmux put it.
tmux -L "$socket" new-window -t work -n pick-me "$IDLE"
tmux -L "$socket" split-window -t "work:pick-me" "$IDLE"
picked_pane=$(tmux -L "$socket" list-panes -t "work:pick-me" -F '#{pane_id}' | tail -1)
other_pane=$(tmux -L "$socket" list-panes -t "work:pick-me" -F '#{pane_id}' | head -1)
tmux -L "$socket" set-option -p -t "$picked_pane" @claude_state asking
tmux -L "$socket" set-option -p -t "$picked_pane" @claude_since "$now"

# select-pane back to the first one, so the assertion cannot pass by accident.
select_first() { tmux -L "$socket" select-pane -t "$other_pane"; }
active_pane() { tmux -L "$socket" display-message -p -t "work:pick-me" '#{pane_id}'; }

# A picker that behaves like fzf closing on a key: the expect line, then the row.
stub_pick() {
  cat >"$work/stub/fzf" <<STUB
#!/bin/sh
row=\$(grep pick-me)
printf '%s\n%s\n' "$1" "\$row"
exit 0
STUB
  chmod +x "$work/stub/fzf"
}

run_pick() {
  select_first
  tmux -L "$socket" run-shell "cd $PWD && PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/out 2>&1"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(active_pane)" = "$picked_pane" ] && return 0
    sleep 0.2
  done
  return 1
}

stub_pick ''
if run_pick; then
  pass "enter selects the picked pane despite the empty --expect line"
else
  fail "enter selects the picked pane despite the empty --expect line" \
    "active pane is $(active_pane), wanted $picked_pane" "$(cat "$work/out" 2>/dev/null)"
fi

# ctrl-o asks for the answer-here view, which needs a client to open a popup on.
# A throwaway server has none, and the rule is that everything the view refuses
# falls through to the jump rather than doing nothing -- so the pane must still
# be selected, and no mirror session may be left behind.
stub_pick 'ctrl-o'
if run_pick; then
  pass "ctrl-o with no client to open a popup on still jumps"
else
  fail "ctrl-o with no client to open a popup on still jumps" \
    "active pane is $(active_pane), wanted $picked_pane" "$(cat "$work/out" 2>/dev/null)"
fi
if tmux -L "$socket" list-sessions -F '#{session_name}' | grep -q '^_agent_'; then
  fail "no mirror session is created when the view is refused" \
    "$(tmux -L "$socket" list-sessions -F '#{session_name}')"
else
  pass "no mirror session is created when the view is refused"
fi

tmux -L "$socket" kill-window -t work:pick-me 2>/dev/null
# Restore the picker stub the sections below expect.
cat >"$work/stub/fzf" <<STUB
#!/bin/sh
cat >"$work/list"
exit 1
STUB
chmod +x "$work/stub/fzf"

# --- the empty case ----------------------------------------------------------

# It must not exit instantly: in a popup that reads as a crash rather than as
# "nothing to show". With no tty it prints the message and returns.
tmux -L "$socket" kill-session -t work 2>/dev/null
tmux -L "$socket" kill-session -t _popup_0 2>/dev/null
tmux -L "$socket" new-session -d -s bare "$IDLE"
rm -f "$work/list"
tmux -L "$socket" run-shell "cd $PWD && PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/empty 2>&1"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  grep -q 'no Claude agents' "$work/empty" 2>/dev/null && break
  sleep 0.2
done
if grep -q 'no Claude agents running' "$work/empty" 2>/dev/null; then
  pass "says so when nothing is running, instead of an empty picker"
else
  fail "says so when nothing is running, instead of an empty picker" "$(cat "$work/empty" 2>/dev/null)"
fi
if [ -f "$work/list" ]; then
  fail "does not open the picker when there is nothing to pick" "fzf was still called"
else
  pass "does not open the picker when there is nothing to pick"
fi

if [ "$failures" -ne 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
