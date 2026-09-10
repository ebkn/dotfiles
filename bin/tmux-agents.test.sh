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
pty_pids=""
cleanup() {
  # shellcheck disable=SC2086 # deliberate word splitting: pty_pids is a list
  [ -n "$pty_pids" ] && kill $pty_pids 2>/dev/null
  tmux -L "$socket" kill-server 2>/dev/null
  rm -rf "$work"
}
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

# The hidden first field is the key the jump and the answer view are driven
# from, and the state rides along in it. ctrl-o is offered only for a session
# that is blocked on the human, and deriving that from the glyph after the fact
# would mean reading the rendering back -- so if the state stops reaching the
# key, ctrl-o silently stops working on exactly the rows it exists for.
check_key_state() {
  local desc=$1 window=$2 want=$3 got
  got=$(grep -F "$window" "$work/list" | head -1 | cut -f1)
  case "$got" in
    *"|$want") pass "$desc" ;;
    *) fail "$desc" "want a key ending in |$want, got: $got" ;;
  esac
}
check_key_state "the key carries the state, for the ctrl-o gate" asking-new  asking
check_key_state "the key carries the state for a waiting row"    waiting-old waiting
check_key_state "the key carries the state for a busy row"       busy-new    busy

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

# enter raises the agent's WezTerm tab, and does NOTHING when there is no such
# tab to raise -- a picker run on an ssh host can never reach the WezTerm in
# front of you, and repointing the tab you are sitting in (which is what the old
# `switch-client` fallback did) is both not what enter means and the two-clients-
# on-one-session state bin/tmux-session-swap exists to prevent. prefix + w is the
# key for that. Nothing here can raise a tab, so nothing may move: in particular
# select-pane must not run, since that would reach into the agent's window.
stub_pick ''
select_first
tmux -L "$socket" run-shell "cd $PWD && PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/out 2>&1"
sleep 1
if [ "$(active_pane)" = "$other_pane" ]; then
  pass "enter with no WezTerm tab to raise leaves the agent's window alone"
else
  fail "enter with no WezTerm tab to raise leaves the agent's window alone" \
    "active pane moved to $(active_pane)" "$(cat "$work/out" 2>/dev/null)"
fi

# ctrl-o needs a client to open a popup on, and a throwaway server has none.
# Refusing must then do NOTHING -- in particular it must not fall back to the
# jump. The two keys mean different things, and a ctrl-o that quietly moved you
# to another tab is worse than one that does not fire.
stub_pick 'ctrl-o'
select_first
tmux -L "$socket" run-shell "cd $PWD && PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/out 2>&1"
sleep 1
if [ "$(active_pane)" = "$other_pane" ]; then
  pass "a refused ctrl-o does not jump"
else
  fail "a refused ctrl-o does not jump" \
    "active pane moved to $(active_pane)" "$(cat "$work/out" 2>/dev/null)"
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

# --- ctrl-o against a real client ---------------------------------------------

# The two things this section pins are the two that were reported broken by eye
# before they were covered, and neither is reachable without an attached client:
# opening the view needs display-popup, and display-popup needs a client.
#
#   * ctrl-o on a session that is NOT blocked must not attach anything. The
#     picker with no client refuses for a different reason (there is nowhere to
#     put a popup), so the case above cannot tell a working gate from a missing
#     one.
#   * the view must be INSET. Sized to the terminal it is indistinguishable from
#     having jumped — "the whole screen changed" — which is a regression a
#     percentage geometry cannot express and only a measurement catches.
#
# The client is a pty from script(1), whose argument order differs between BSD
# and GNU; both spellings are tried. Inside the popup tmux sets $TMUX, so a bare
# `tmux` in the script under test reaches this server with no shim.
# `sleep` on stdin, deliberately: script(1) copies its own stdin into the pty it
# creates and exits when that stdin reaches EOF, taking the tmux client with it.
# Run from a test whose stdin is an exhausted pipe that is immediate, and the
# client never appears -- which is the intermittent "no pty client" failure this
# suite used to show about once in ten runs. A pipe nobody ever writes to keeps
# the pty open for as long as the test needs it.
pty_attach() {
  # Output kept, not discarded: when this fails the reason is in it, and a
  # failure with no diagnostic is what made this flake take three sittings.
  #
  # The BSD/GNU split is decided from $OSTYPE, NOT by running `script` and
  # seeing whether it succeeds. That probe was the flake: it spawns a pty of its
  # own, and when it failed -- which it did about one run in ten, under load or
  # with the caller's stdin already closed -- the code fell through to the GNU
  # spelling on a BSD script(1), which answers "illegal option -- c" and leaves
  # no client behind. A platform is not something to discover by trial.
  #
  # $TMUX is cleared for the attach. The suite is normally run from inside tmux,
  # and tmux then refuses the attach as nested ("sessions should be nested with
  # care") even though this is a different socket -- silently, since the client
  # simply never appears. Nothing here wants nesting semantics: the throwaway
  # server is not the one the test is being typed into.
  #
  # SSH_CONNECTION is cleared as well, and with `env -u` rather than an empty
  # value: it is in tmux's default update-environment, so an attaching client
  # that has it makes the session look like an ssh login to the jump -- which is
  # true of every client attached from a suite run over ssh, and would make the
  # WezTerm cases below unreachable on exactly the machines they matter least to
  # break on. `-u` removes it from the session environment; SSH_CONNECTION= would
  # set it to the empty string, which still reads as present.
  if [ "${OSTYPE:-}" != "${OSTYPE#darwin}" ]; then
    { sleep 120 | env -u TMUX -u SSH_CONNECTION script -q /dev/null tmux -L "$socket" attach -t "$1"; } >"$work/pty.log" 2>&1 &
  else
    { sleep 120 | env -u TMUX -u SSH_CONNECTION script -q -c "tmux -L $socket attach -t $1" /dev/null; } >"$work/pty.log" 2>&1 &
  fi
  # Remembered so cleanup can end it: the sleep outlives the test otherwise, and
  # anything inheriting its stdout would wait two minutes for the pipe to close.
  pty_pids="${pty_pids:-} $!"
}

# Defined out here, not inside the block that uses it: when the pty client could
# not be attached that block is skipped, and a helper defined inside it would
# take out every later section with "command not found" -- turning one honest
# failure into three misleading ones.
mirrors() { tmux -L "$socket" list-sessions -F '#{session_name}' | grep -c '^_agent_' || true; }

tmux -L "$socket" new-session -d -s tabA "$IDLE"
tmux -L "$socket" new-session -d -s tabB -n busy-win "$IDLE"
tmux -L "$socket" new-window -t tabB -n ask-win "$IDLE"
for wn in busy-win:busy ask-win:asking; do
  p=$(tmux -L "$socket" list-panes -t "tabB:${wn%%:*}" -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$p" @claude_state "${wn##*:}"
  tmux -L "$socket" set-option -p -t "$p" @claude_since "$(date +%s)"
done

# The attach is retried once: script(1) backgrounded from here occasionally
# never gets going at all, which showed up as roughly one run in ten failing
# with no client rather than as anything to do with the code under test.
client=""
for _ in 1 2; do
  pty_attach tabA
  for _ in $(seq 1 24); do
    client=$(tmux -L "$socket" list-clients -F '#{client_name}' | head -1)
    [ -n "$client" ] && break
    sleep 0.25
  done
  [ -n "$client" ] && break
done

if [ -z "$client" ]; then
  fail "a pty client can be attached for the ctrl-o cases" \
    "script(1) produced no client; the cases below are untested" \
    "script output: [$(tr -d '\r' <"$work/pty.log" 2>/dev/null | head -3 | tr '\n' '|')]" \
    "sessions: $(tmux -L "$socket" list-sessions -F '#{session_name}' 2>&1 | tr '\n' ' ')"
else
  # Picks the row whose window name is in $PICK and reports it as chosen with
  # ctrl-o, which is what --expect prints on its own first line.
  cat >"$work/stub/fzf" <<STUB
#!/bin/sh
cat >"$work/list"
printf 'ctrl-o\n%s\n' "\$(grep \$PICK "$work/list")"
exit 0
STUB
  chmod +x "$work/stub/fzf"

  press_ctrl_o() {
    tmux -L "$socket" display-popup -c "$client" -E -w 60 -h 20 \
      "sh -c 'PICK=$1 PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/out 2>&1'"
    sleep 2
  }
  press_ctrl_o busy-win
  if [ "$(mirrors)" = 0 ]; then
    pass "ctrl-o on a session that is not blocked attaches nothing"
  else
    fail "ctrl-o on a session that is not blocked attaches nothing" \
      "$(tmux -L "$socket" list-sessions -F '#{session_name}')"
  fi
  # And it does not jump either: the client must still be on the session it was
  # attached to. This is the half a headless run cannot see, since with no
  # client there is no session for a jump to move.
  on=$(tmux -L "$socket" list-clients -F '#{client_name} #{client_session}' |
    awk -v c="$client" '$1 == c { print $2 }')
  if [ "$on" = tabA ]; then
    pass "a refused ctrl-o leaves the client where it was"
  else
    fail "a refused ctrl-o leaves the client where it was" "client moved to $on"
  fi

  press_ctrl_o ask-win
  # Both sizes come out of one list-clients, matched by name. `display-message
  # -p -c <client> '#{client_width}'` does NOT report that client here -- with a
  # popup open it answered with the popup's size, which made the assertion below
  # compare the mirror against itself and pass for the wrong reason.
  clients=$(tmux -L "$socket" list-clients -F '#{client_name} #{client_session} #{client_width} #{client_height}')
  read -r cli_w cli_h < <(awk -v c="$client" '$1 == c { print $3, $4; exit }' <<<"$clients")
  read -r mir_w mir_h < <(awk '$2 ~ /^_agent_/ { print $3, $4; exit }' <<<"$clients")
  if [ -n "${mir_w:-}" ]; then
    pass "ctrl-o on a blocked session opens the view"
    if [ "$mir_w" -lt "$cli_w" ] && [ "$mir_h" -lt "$cli_h" ]; then
      pass "the view is inset, not the whole terminal (${mir_w}x${mir_h} in ${cli_w}x${cli_h})"
    else
      fail "the view is inset, not the whole terminal" \
        "view ${mir_w}x${mir_h}, terminal ${cli_w}x${cli_h}"
    fi
  else
    fail "ctrl-o on a blocked session opens the view" "no _agent_ client attached" \
      "$(cat "$work/out" 2>/dev/null)"
  fi

  for m in $(tmux -L "$socket" list-clients -F '#{client_name} #{client_session}' |
    awk '$2 ~ /^_agent_/ { print $1 }'); do
    tmux -L "$socket" detach-client -t "$m" 2>/dev/null
  done
fi

# --- the real fzf binding ------------------------------------------------------

# Every case above stubs fzf, which means none of them touch the --bind that
# actually decides whether ctrl-o does anything. That binding is where the
# behaviour lives: refusing after the picker has closed can only close the popup
# and print to the status line, which is itself something happening, so the
# refusal is made inside fzf and leaves the list standing with a warning in its
# header. It is also the most fragile part of the script -- a shell case
# statement inside a --bind inside a shell string -- and when the quoting is
# wrong fzf simply does nothing, which looks exactly like a working refusal.
#
# So this drives the real thing: the picker runs in a real pane (fzf needs a
# terminal), keys go in with send-keys, and the assertions read the rendered
# screen. `remain-on-exit` keeps the pane inspectable after fzf accepts, which
# is how acceptance is told apart from a binding that quietly did nothing.
# The mirror opened above is torn down asynchronously, and its popup lives on
# the client attached to tabA -- so wait for it to be gone before killing that
# client out from under it, rather than racing the teardown.
for _ in $(seq 1 20); do
  tmux -L "$socket" list-clients -F '#{client_session}' 2>/dev/null |
    grep -q '^_agent_' || break
  sleep 0.25
done
tmux -L "$socket" kill-session -t tabA 2>/dev/null
tmux -L "$socket" kill-session -t tabB 2>/dev/null
tmux -L "$socket" new-session -d -s bindA -x 100 -y 14 "$IDLE"
tmux -L "$socket" set-option -t bindA remain-on-exit on
tmux -L "$socket" new-session -d -s bindB -n b-busy "$IDLE"
tmux -L "$socket" new-window -t bindB -n b-ask "$IDLE"
for pair in b-busy:busy b-ask:asking; do
  p=$(tmux -L "$socket" list-panes -t "bindB:${pair%%:*}" -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$p" @claude_state "${pair##*:}"
  tmux -L "$socket" set-option -p -t "$p" @claude_since "$(date +%s)"
done

fzf_pane=$(tmux -L "$socket" list-panes -t bindA -F '#{pane_id}' | head -1)
tmux -L "$socket" respawn-pane -k -t "$fzf_pane" \
  "sh -c 'PATH=$PWD/bin:\$PATH tmux-agents >$work/real 2>&1'"

screen() { tmux -L "$socket" capture-pane -p -t "$fzf_pane"; }
dead() { tmux -L "$socket" display-message -p -t "$fzf_pane" '#{pane_dead}'; }

# Polled rather than slept on. A fixed wait long enough for a loaded machine is
# dead time on every run, and one that is merely usually long enough is a test
# that fails for reasons that have nothing to do with the code.
wait_screen() {
  for _ in $(seq 1 40); do
    grep -q -- "$1" <<<"$(screen)" && return 0
    sleep 0.25
  done
  return 1
}

if ! wait_screen 'b-ask'; then
  fail "the picker renders in a real pane" "$(screen)" "$(cat "$work/real" 2>/dev/null)"
else
  pass "the picker renders in a real pane"

  # asking sorts above busy, so the second row is the one ctrl-o must refuse.
  tmux -L "$socket" send-keys -t "$fzf_pane" Down
  sleep 0.4
  tmux -L "$socket" send-keys -t "$fzf_pane" C-o

  if wait_screen 'not waiting on you'; then
    pass "ctrl-o on a row that is not blocked warns in the header"
  else
    fail "ctrl-o on a row that is not blocked warns in the header" "$(screen)"
  fi
  after=$(screen)
  if [ "$(dead)" = 0 ] && grep -q 'b-busy' <<<"$after"; then
    pass "the refused ctrl-o leaves the picker open"
  else
    fail "the refused ctrl-o leaves the picker open" "pane_dead=$(dead)" "$after"
  fi

  # Moving the cursor must put the hint back, or the warning strands you with no
  # reminder of what either key does.
  tmux -L "$socket" send-keys -t "$fzf_pane" Up
  if wait_screen 'enter: jump to the tab'; then
    pass "moving off the row restores the hint"
  else
    fail "moving off the row restores the hint" "$(screen)"
  fi

  # And the eligible row still accepts. There is no client here, so the script
  # stops at its own no-client guard -- but fzf having accepted is what makes
  # the pane exit at all, and exit 0 is what says it got that far.
  tmux -L "$socket" send-keys -t "$fzf_pane" C-o
  for _ in $(seq 1 40); do
    [ "$(dead)" = 1 ] && break
    sleep 0.25
  done
  if [ "$(dead)" = 1 ]; then
    pass "ctrl-o on a blocked row is accepted"
  else
    fail "ctrl-o on a blocked row is accepted" "picker still running" "$(screen)"
  fi

  # --- enter, through the real fzf ---------------------------------------------
  #
  # enter and ctrl-o are two different features and must stay that way: enter
  # raises the agent's WezTerm tab, ctrl-o brings the agent here. Everything
  # above that exercises enter does it through a STUBBED fzf, so the binding
  # enter actually runs -- `enter:print()+accept`, which replaced --expect when
  # ctrl-o became a transform -- was never covered. If that print() ever stops
  # emitting its empty first line, the row is read one line off and the jump
  # silently targets nothing; if it emitted the wrong key name, enter would open
  # the answer view instead.
  #
  # Both halves of the jump are covered, because both are silent when wrong:
  # with no WezTerm tab to raise, NOTHING may happen (not even select-pane);
  # with one, the tab must actually be raised. The second needs a `wezterm` that
  # answers, so it is stubbed -- the real one cannot be driven from a test, and
  # a machine with no WezTerm would otherwise leave the whole success path
  # untested. jq is NOT stubbed: the filter that matches client_tty against
  # tty_name is this repo's, and it is exactly the part that can rot.
  tmux -L "$socket" new-window -t bindB -n b-jump "$IDLE"
  tmux -L "$socket" split-window -t bindB:b-jump "$IDLE"
  jump_target=$(tmux -L "$socket" list-panes -t bindB:b-jump -F '#{pane_id}' | tail -1)
  jump_other=$(tmux -L "$socket" list-panes -t bindB:b-jump -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$jump_target" @claude_state waiting
  tmux -L "$socket" set-option -p -t "$jump_target" @claude_since "$(date +%s)"

  # press_enter <window name> — type enough to select that row, then Enter.
  press_enter() {
    tmux -L "$socket" select-pane -t "$jump_other"
    tmux -L "$socket" respawn-pane -k -t "$fzf_pane" \
      "sh -c 'PATH=$work/wstub:$PWD/bin:\$PATH tmux-agents >$work/real2 2>&1'"
    wait_screen "$1" || return 1
    tmux -L "$socket" send-keys -t "$fzf_pane" "$1"
    sleep 0.4
    tmux -L "$socket" send-keys -t "$fzf_pane" Enter
    for _ in $(seq 1 40); do
      [ "$(dead)" = 1 ] && break
      sleep 0.25
    done
    return 0
  }

  # A directory of its own, NOT $work/stub: that one holds the fzf stub, and
  # putting it on the path here would replace the real fzf this section exists
  # to drive -- the picker would render nothing and every case below would fail
  # for a reason that has nothing to do with the jump.
  mkdir -p "$work/wstub"
  rm -f "$work/wstub/wezterm"
  if ! press_enter b-jump; then
    fail "the picker lists the jump fixture" "$(screen)"
  else
    active=$(tmux -L "$socket" display-message -p -t bindB:b-jump '#{pane_id}')
    if [ "$active" = "$jump_other" ]; then
      pass "enter with no WezTerm tab to raise touches nothing"
    else
      fail "enter with no WezTerm tab to raise touches nothing" \
        "active pane moved to $active" "$(cat "$work/real2" 2>/dev/null)"
    fi
    if [ "$(mirrors)" = 0 ]; then
      pass "enter opens no answer view -- the two keys stay separate features"
    else
      fail "enter opens no answer view -- the two keys stay separate features" \
        "$(tmux -L "$socket" list-sessions -F '#{session_name}')"
    fi
  fi

  # Now with a WezTerm that answers. The stub reports the tty of the client
  # attached to the agent's window, which is what the jump has to match on --
  # get that lookup wrong and it silently reports no tab, i.e. the case above.
  pty_attach bindB
  agent_tty=""
  for _ in $(seq 1 24); do
    agent_tty=$(tmux -L "$socket" list-clients -F '#{client_name} #{client_session}' |
      awk '$2 == "bindB" { print $1; exit }')
    [ -n "$agent_tty" ] && break
    sleep 0.25
  done

  if [ -z "$agent_tty" ]; then
    fail "a pty client can be attached to the agent's session" \
      "script output: [$(tr -d '\r' <"$work/pty.log" 2>/dev/null | head -3 | tr '\n' '|')]"
  else
    cat >"$work/wstub/wezterm" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$work/wezterm-calls"
case "\$*" in
  *list*) printf '[{"tab_id": 77, "tty_name": "%s"}]\n' "$agent_tty" ;;
esac
exit 0
STUB
    chmod +x "$work/wstub/wezterm"
    : >"$work/wezterm-calls"

    if ! press_enter b-jump; then
      fail "the picker lists the jump fixture (wezterm case)" "$(screen)"
    else
      if grep -q 'activate-tab --tab-id 77' "$work/wezterm-calls" 2>/dev/null; then
        pass "enter raises the WezTerm tab that shows the agent's window"
      else
        fail "enter raises the WezTerm tab that shows the agent's window" \
          "wezterm calls: [$(tr '\n' '|' <"$work/wezterm-calls" 2>/dev/null)]" \
          "$(cat "$work/real2" 2>/dev/null)"
      fi
      # Every wezterm call has to carry --no-auto-start. Without it the CLI
      # tries to START a mux server before admitting there is none: measured at
      # 3.0-3.4s against 0.00s with the flag, and that delay lands between
      # pressing enter and the warning, on exactly the hosts where the warning
      # is the normal answer. A missing flag is invisible to every other
      # assertion here -- the jump still works, it is just slow.
      slow=$(grep -cv -- '--no-auto-start' "$work/wezterm-calls" 2>/dev/null || true)
      if [ "${slow:-0}" -eq 0 ]; then
        pass "wezterm is never allowed to auto-start a mux server"
      else
        fail "wezterm is never allowed to auto-start a mux server" \
          "calls without the flag: [$(grep -v -- '--no-auto-start' "$work/wezterm-calls" | tr '\n' '|')]"
      fi
      active=$(tmux -L "$socket" display-message -p -t bindB:b-jump '#{pane_id}')
      if [ "$active" = "$jump_target" ]; then
        pass "and puts the agent's pane in front inside it"
      else
        fail "and puts the agent's pane in front inside it" \
          "active pane is $active, wanted $jump_target"
      fi
    fi
    # And the ssh case: a client attached over ssh is never a WezTerm tab, so
    # the CLI must not be run at all. This is the normal state of every row when
    # the picker itself runs on a remote host, and running wezterm there is pure
    # latency for an answer already known -- the assertion is therefore that the
    # stub recorded NOTHING, not merely that the jump was refused.
    tmux -L "$socket" set-environment -t bindB SSH_CONNECTION "10.0.0.1 1 10.0.0.2 22"
    : >"$work/wezterm-calls"
    if ! press_enter b-jump; then
      fail "the picker lists the jump fixture (ssh case)" "$(screen)"
    else
      if [ ! -s "$work/wezterm-calls" ]; then
        pass "enter on a window shown over ssh never runs wezterm at all"
      else
        fail "enter on a window shown over ssh never runs wezterm at all" \
          "wezterm calls: [$(tr '\n' '|' <"$work/wezterm-calls")]"
      fi
      active=$(tmux -L "$socket" display-message -p -t bindB:b-jump '#{pane_id}')
      if [ "$active" = "$jump_other" ]; then
        pass "and touches nothing"
      else
        fail "and touches nothing" "active pane moved to $active"
      fi
    fi
    tmux -L "$socket" set-environment -u -t bindB SSH_CONNECTION

    rm -f "$work/wstub/wezterm"
  fi
fi

if [ "$failures" -ne 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
