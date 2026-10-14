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
# A tmux suite: container or CI only (see bin/tmux-test-guard.sh).
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux-agents.test: tmux is required" >&2
  exit 1
fi

socket="agents-test-$$"
work=$(mktemp -d)
pty_pids=""

# A server on the DEFAULT socket of a private TMUX_TMPDIR, reached the way a
# client with no $TMUX reaches the real one -- launchd, an ssh exec. $TMUX is
# removed here rather than trusted to be unset: with no -L/-S, tmux prefers the
# socket named in $TMUX over TMUX_TMPDIR, so one inherited value would send a
# fixture's new-session, and its kill-server, to some other server.
bare_tmux() { # $1 private TMUX_TMPDIR, then tmux arguments
  local dir=$1
  shift
  env -u TMUX TMUX_TMPDIR="$dir" tmux "$@"
}

cleanup() {
  # shellcheck disable=SC2086 # deliberate word splitting: pty_pids is a list
  [ -n "$pty_pids" ] && kill $pty_pids 2>/dev/null
  tmux -L "$socket" kill-server 2>/dev/null
  # Any bare_tmux server, should its case die before its own kill-server.
  for d in "$work"/*-tmpdir; do
    [ -d "$d" ] && bare_tmux "$d" kill-server 2>/dev/null
  done
  rm -rf "$work"
}
trap cleanup EXIT

failures=0
fail() {
  printf 'FAIL %s\n' "$1"
  shift
  for l in "$@"; do printf '  %s\n' "$l"; done
  failures=$((failures + 1))
}
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

base_fixtures() {
  tmux -L "$socket" -f /dev/null new-session -d -s work "$IDLE"
  add_pane busy-new busy 10
  add_pane stalled-old stalled 7200
  add_pane asking-new asking 30 "which one?"
  add_pane waiting-old waiting 600 "needs permission"
  add_pane needs-input needs_input 120 "reviewer needs your input"
  # 400000s renders as "111h", four characters. That width is deliberate: the
  # age is printed with %4s, so for the usual three-character age ("10s", "2h")
  # the right-alignment contributes a leading space that exactly replaces the ▶
  # glyph's own padding -- and the glyph assertion below would pass even with
  # the padding removed. Only a four-character age makes the padding observable.
  add_pane busy-old busy 400000

  # A pane with no agent at all must not appear.
  tmux -L "$socket" new-window -t work -n plain-pane "$IDLE"

  # A popup session, named the way bin/tmux-popup names them, carrying state.
  # The picker must skip it.
  tmux -L "$socket" new-session -d -s _popup_0 "$IDLE"
  local popup_pane
  popup_pane=$(tmux -L "$socket" list-panes -t _popup_0 -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$popup_pane" @claude_state busy
  tmux -L "$socket" set-option -p -t "$popup_pane" @claude_since "$now"
}

# fresh_server [bare] -- a new server for the next phase, holding the base
# fixtures (or, with `bare`, one empty session). Each phase of this file starts
# from one, rather than from whatever the phase before it added, renamed or
# killed: the suite used to run every case on one server kept consistent by
# hand, and two silent false passes came out of state it leaked
# (tmux-agents.md). Waits for the old server to be gone, or the new-session
# could land on the dying one.
fresh_server() {
  tmux -L "$socket" kill-server 2>/dev/null
  for _ in $(seq 1 50); do
    tmux -L "$socket" list-sessions >/dev/null 2>&1 || break
    sleep 0.1
  done
  if [ "${1:-}" = bare ]; then
    tmux -L "$socket" -f /dev/null new-session -d -s bare "$IDLE"
  else
    base_fixtures
  fi
}

fresh_server

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
if [ "$listed" -eq 6 ]; then
  pass "lists exactly the six panes that have state"
else
  fail "lists exactly the six panes that have state" "got $listed" "$(cat "$work/list")"
fi

# --- ranking -----------------------------------------------------------------

# Every state blocked on the human -- asking, waiting and needs_input -- shares
# the top rank, and within it the one blocked longest comes first: ctrl-o
# answers all three where you are, so none of them is "somewhere you have to
# go" any more. Then busy, oldest first; then everything else.
expected_order='waiting-old
needs-input
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
# asking, waiting and needs_input deliberately print the SAME glyph: which kind
# of block it is does not change the answer to the question the indicator is
# asked. All three are asserted anyway — "they happen to agree" and "they are
# meant to agree" are different claims, and only the second survives someone
# changing one of them.
check_glyph "asking renders as the stop sign plus one space" asking-new '🛑 '
check_glyph "waiting renders as the stop sign plus one space" waiting-old '🛑 '
check_glyph "stalled renders as the green circle plus one space" stalled-old '🟢 '
check_glyph "needs_input renders as the same stop sign" needs-input '🛑 '
# Checked on the row with the four-character age, for the reason given where
# busy-old is created: a shorter age hides a missing pad behind %4s.
check_glyph "busy renders as ▶ padded out to the same two cells" busy-old '▶  '

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
check_age "an age under an hour is shown in minutes" waiting-old '10m'
check_age "an age over an hour is shown in hours" stalled-old '2h'
check_age "an age of many hours is not abbreviated" busy-old '111h'

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
check_key_state "the key carries the state, for the ctrl-o gate" asking-new asking
check_key_state "the key carries the state for a waiting row" waiting-old waiting
check_key_state "the key carries the state for a busy row" busy-new busy

# --- one row per actor ---------------------------------------------------------

# A pane running subagents holds several states at once, and agent-state.sh
# publishes them as @claude_agents alongside the aggregate. Expanding that into
# a row each is the whole reason the picker exists in a world with subagents:
# with only the aggregate, three agents where one is blocked look exactly like
# three agents where none is, and the tab glyph already told you that much.
RS=$'\036'
US=$'\037'

tmux -L "$socket" new-window -t work -n multi-win "$IDLE"
multi_pane=$(tmux -L "$socket" list-panes -t work:multi-win -F '#{pane_id}' | head -1)
# The aggregate, as the hook would publish it: the blocked subagent wins.
tmux -L "$socket" set-option -p -t "$multi_pane" @claude_state waiting
tmux -L "$socket" set-option -p -t "$multi_pane" @claude_since "$((now - 300))"
multi_listing="busy${US}$((now - 5))${US}${US}${RS}"
multi_listing+="waiting${US}$((now - 300))${US}Explore${US}needs permission${RS}"
multi_listing+="busy${US}$((now - 20))${US}Plan${US}${RS}"
# A record with no state is not an actor, and must be skipped rather than
# rendered as a plausible grey circle with no age. Only the hook writes this
# option, so the way one arrives is truncation or a stray writer -- but the row
# it produces looks exactly like a real agent, which is why it is pinned.
multi_listing+="${US}$((now - 10))${US}${US}${RS}"
tmux -L "$socket" set-option -p -t "$multi_pane" @claude_agents "$multi_listing"

if run_picker; then
  rows=$(grep -c 'multi-win' "$work/list" || true)
  if [ "$rows" -eq 3 ]; then
    pass "a pane with three actors contributes three rows, and the state-less record none"
  else
    fail "a pane with three actors contributes three rows, and the state-less record none" \
      "got $rows" "$(grep 'multi-win' "$work/list")"
  fi

  # The aggregate must not be emitted on top of the listing: it is derived from
  # exactly those records, so a fourth row would be one of them counted twice.
  agg=$(grep 'multi-win' "$work/list" | grep -c 'needs permission' || true)
  if [ "$agg" -eq 1 ]; then
    pass "the aggregate is not listed again beside the actors it summarises"
  else
    fail "the aggregate is not listed again beside the actors it summarises" "got $agg rows"
  fi

  # The key carries the *actor's* state, not the pane's aggregate: ctrl-o is
  # offered per row, and a busy subagent's row must not inherit the right to
  # answer a dialog belonging to a different actor in the same pane.
  blocked_key=$(grep 'multi-win' "$work/list" | grep -F 'Explore' | head -1 | cut -f1)
  case "$blocked_key" in
    *'|waiting') pass "an actor row's key carries that actor's state" ;;
    *) fail "an actor row's key carries that actor's state" "key: ${blocked_key:-<missing>}" ;;
  esac
  running_key=$(grep 'multi-win' "$work/list" | grep -F 'Plan' | head -1 | cut -f1)
  case "$running_key" in
    *'|busy') pass "a running actor's row is not keyed as blocked" ;;
    *) fail "a running actor's row is not keyed as blocked" "key: ${running_key:-<missing>}" ;;
  esac

  blocked=$(grep 'multi-win' "$work/list" | grep -F 'Explore' | cut -f2-)
  case "$blocked" in
    '🛑 '*) pass "the blocked subagent keeps its own glyph, not the pane's" ;;
    *) fail "the blocked subagent keeps its own glyph, not the pane's" "row: ${blocked:-<missing>}" ;;
  esac
  case "$blocked" in
    *"multi-win [Explore]"*"needs permission"*)
      pass "the row names which subagent it is and carries its note"
      ;;
    *) fail "the row names which subagent it is and carries its note" "row: ${blocked:-<missing>}" ;;
  esac

  # Ranking is per actor too: the blocked subagent sorts above every busy row,
  # including the two from its own pane. Anything else and the row that needs a
  # human is below the fold, which is the failure this picker exists to prevent.
  first=$(cut -f2- "$work/list" | head -1 | awk '{ print $4 }')
  if [ "$first" = "waiting-old" ]; then
    pass "actor rows join the same ranking as pane rows"
  else
    fail "actor rows join the same ranking as pane rows" "first row is $first"
  fi
  # head -1 on both: a second match -- a note that happens to mention Explore --
  # would make these two line numbers instead of one, and the comparison below
  # then dies with "integer expression expected" rather than saying anything
  # about ranking.
  explore_pos=$(cut -f2- "$work/list" | grep -n 'Explore' | head -1 | cut -d: -f1)
  busy_pos=$(cut -f2- "$work/list" | grep -n 'busy-old' | head -1 | cut -d: -f1)
  if [ "$explore_pos" -lt "$busy_pos" ]; then
    pass "a blocked subagent outranks a busy pane"
  else
    fail "a blocked subagent outranks a busy pane" "Explore at $explore_pos, busy-old at $busy_pos"
  fi
else
  fail "the per-actor path produces a list" "fzf stub was never reached"
fi

# --- a listing that arrived escaped, as an older tmux hands it over ------------
#
# The separators are ASCII RS/US, and an older tmux does not store them: measured
# on 3.4, `set-option` rewrites each one as the four literal characters \036 /
# \037, and they come back that way out of `show-options` as well as out of a
# format -- so it is the option store, not the format expansion. 3.7c, the pinned
# version, round-trips them untouched.
#
# That matters over ssh, where the REMOTE tmux expands the format, so the version
# under the rows is not the version this suite runs. The listing then arrives as
# one record where it plainly held several, the picker shows one garbled row, and
# the blocked subagent inside it is invisible -- the one failure this list exists
# to prevent. The aggregate options carry no control characters and were never
# affected, which is exactly why nothing noticed.
#
# Written here as the literal escaped text rather than by installing an old tmux:
# what the consumer has to cope with is the bytes that arrive, and those are
# measured above. The real 3.4 is checked by hand, not from CI, which has one
# pinned version by design.
tmux -L "$socket" new-window -t work -n esc-win "$IDLE"
esc_pane=$(tmux -L "$socket" list-panes -t work:esc-win -F '#{pane_id}' | head -1)
tmux -L "$socket" set-option -p -t "$esc_pane" @claude_state waiting
tmux -L "$socket" set-option -p -t "$esc_pane" @claude_since "$((now - 300))"
esc_listing='busy\037'"$((now - 20))"'\037Plan\037\036'
esc_listing+='waiting\037'"$((now - 300))"'\037Explore\037needs permission\036'
tmux -L "$socket" set-option -p -t "$esc_pane" @claude_agents "$esc_listing"

if run_picker; then
  rows=$(grep -c 'esc-win' "$work/list" || true)
  if [ "$rows" -eq 2 ]; then
    pass "an escaped listing still contributes one row per actor"
  else
    fail "an escaped listing still contributes one row per actor" \
      "got $rows" "$(grep 'esc-win' "$work/list")"
  fi

  # Not just the count: the fields inside a record are separated by US, which is
  # escaped the same way. A row that split on RS but not US would still be one
  # row per actor while showing the whole record as the window name.
  esc_blocked=$(grep 'esc-win' "$work/list" | grep -F 'Explore' | cut -f2-)
  case "$esc_blocked" in
    '🛑 '*"esc-win [Explore]"*"needs permission"*)
      pass "and its fields are separated, not shown as one blob"
      ;;
    *)
      fail "and its fields are separated, not shown as one blob" \
        "row: ${esc_blocked:-<missing>}"
      ;;
  esac

  # The escaped text must not survive into what is displayed. A row reading
  # `\037` is a visible artefact even when the split happened to work.
  case $(grep 'esc-win' "$work/list") in
    *'\03'*) fail "no escape sequence is left in the rendered row" \
      "$(grep 'esc-win' "$work/list")" ;;
    *) pass "no escape sequence is left in the rendered row" ;;
  esac
else
  fail "the escaped-listing path produces a list" "fzf stub was never reached"
fi

# A row the CURRENT tmux wrote, whose note happens to contain that escape as
# literal text. Normalising it would turn the note's own characters into a record
# separator and split the record in half -- the exact confusion the raw bytes were
# chosen to avoid, arriving from the other direction. A listing written by a tmux
# that stores the bytes always carries at least one real RS, because every record
# ends with one, so that is what tells the two apart. Per row and not per run:
# a local pane on the pinned tmux and a remote one on an older tmux appear in the
# same listing, and each needs the opposite treatment.
tmux -L "$socket" new-window -t work -n lit-win "$IDLE"
lit_pane=$(tmux -L "$socket" list-panes -t work:lit-win -F '#{pane_id}' | head -1)
tmux -L "$socket" set-option -p -t "$lit_pane" @claude_state waiting
tmux -L "$socket" set-option -p -t "$lit_pane" @claude_since "$((now - 60))"
tmux -L "$socket" set-option -p -t "$lit_pane" @claude_agents \
  "waiting${US}$((now - 60))${US}Explore${US}what is \\036 for${RS}busy${US}$((now - 5))${US}${US}${RS}"

if run_picker; then
  lit_rows=$(grep -c 'lit-win' "$work/list" || true)
  if [ "$lit_rows" -eq 2 ]; then
    pass "a listing with real separators is left alone though its note holds the escape"
  else
    fail "a listing with real separators is left alone though its note holds the escape" \
      "got $lit_rows" "$(grep 'lit-win' "$work/list")"
  fi
  lit_note=$(grep 'lit-win' "$work/list" | grep -F 'Explore' | cut -f2-)
  case "$lit_note" in
    *'what is \036 for'*) pass "and the note keeps the escape as the text it is" ;;
    *) fail "and the note keeps the escape as the text it is" "row: ${lit_note:-<missing>}" ;;
  esac
else
  fail "the literal-escape-in-note path produces a list" "fzf stub was never reached"
fi

# --- corrected against the session's own view ---------------------------------

fresh_server

# The pane options are transitions reported by hooks, and three transitions have
# no hook at all: a permission prompt being answered, a dialog being dismissed,
# and a turn being interrupted. So the options go stale in exactly the cases
# this list exists to show, and `tmux-agents --rows` -- what the picker reloads
# itself from -- merges in what `claude agents --json` says.
#
# These drive that mode directly. It runs the same render as the picker, so what
# it prints is what a refreshed picker shows, and the fzf stub is not involved.

# A stub `claude`, because the real one would answer about the sessions this
# developer has open, which are not the fixtures.
stub_claude() { # $1 json array, or "fail" for a CLI that cannot answer
  if [ "$1" = fail ]; then
    printf '#!/bin/sh\nexit 1\n' >"$work/stub/claude"
  else
    {
      printf '#!/bin/sh\n'
      printf "cat <<'JSON'\n%s\nJSON\n" "$1"
    } >"$work/stub/claude"
  fi
  chmod +x "$work/stub/claude"
}

add_bound_pane() { # $1 window name, $2 state, $3 note, $4 session id
  local pane
  tmux -L "$socket" new-window -t work -n "$1" "$IDLE"
  pane=$(tmux -L "$socket" list-panes -t "work:$1" -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$pane" @claude_state "$2"
  tmux -L "$socket" set-option -p -t "$pane" @claude_since "$now"
  [ -n "$3" ] && tmux -L "$socket" set-option -p -t "$pane" @claude_note "$3"
  [ -n "$4" ] && tmux -L "$socket" set-option -p -t "$pane" @claude_session_id "$4"
}

# corr-stale also carries a per-actor listing, because that is the path that
# would otherwise put the stale rows straight back: the listing is derived from
# the same records the CLI has just contradicted.
add_bound_pane corr-stale waiting "needs permission" sid-stale
stale_pane=$(tmux -L "$socket" list-panes -t work:corr-stale -F '#{pane_id}' | head -1)
tmux -L "$socket" set-option -p -t "$stale_pane" @claude_agents \
  "waiting${US}${now}${US}Explore${US}needs permission${RS}busy${US}${now}${US}${US}${RS}"
add_bound_pane corr-late busy "" sid-late
# needs_input is the third blocked state, and it reaches red by a different
# route (a worker agent, not a dialog here). A correction that only knew about
# asking and waiting would leave exactly this one stuck.
add_bound_pane corr-needs needs_input "a worker needs you" sid-needs
# asking is the first blocked state, and without a fixture of its own a rule
# that hard-coded `waiting|needs_input` instead of reading BLOCKED_STATES would
# leave it stuck red -- the drift between copies that list exists to prevent.
add_bound_pane corr-asking asking "which approach?" sid-asking
add_bound_pane corr-unknown waiting "needs permission" sid-unknown
# `shell` is NOT the example of an unknown status any more, because it is not one:
# the CLI's own bundle derives it as `status === "idle" && <in a shell> ? "shell"
# : status`, so it is a flavour of idle and belongs in the recognised set. A value
# that is genuinely outside the vocabulary is needed to keep pinning the rule, and
# it has to stay outside it -- so something no CLI would emit.
add_bound_pane corr-shell waiting "needs permission" sid-shell
add_bound_pane corr-nobind waiting "needs permission" ""
# A binding whose session the CLI does not list: the session ended while the
# pane stayed open. Absence is not evidence that it is unblocked.
add_bound_pane corr-gone waiting "needs permission" sid-gone
# Running versus idle, neither one blocked. Hooks miss both directions: an
# interrupted subagent fires no SubagentStop, so its `busy` record holds the pane
# at ▶ after the session has gone idle; and a turn can start without
# UserPromptSubmit (woken by a background task), leaving 🟢 on a running session.
#
# Each carries the listing the hook really publishes, because render_list builds
# rows from the listing whenever there is one: corr-idle is the reported pane
# (main stalled, an interrupted subagent busy), so the correction must drop the
# listing here too, or its ▶ row is drawn regardless of the corrected aggregate.
add_bound_pane corr-idle busy "" sid-idle
tmux -L "$socket" set-option -p -t "$(tmux -L "$socket" list-panes -t work:corr-idle -F '#{pane_id}' | head -1)" \
  @claude_agents "stalled${US}${now}${US}${US}${RS}busy${US}${now}${US}general-purpose${US}${RS}"
add_bound_pane corr-running stalled "" sid-running
tmux -L "$socket" set-option -p -t "$(tmux -L "$socket" list-panes -t work:corr-running -F '#{pane_id}' | head -1)" \
  @claude_agents "stalled${US}${now}${US}${US}${RS}"
# `shell` is idle, so a busy pane under it goes green, not left as running.
add_bound_pane corr-shellbusy busy "" sid-shellbusy
# What the running/idle rule must NOT reach, with the CLI saying busy so that
# reaching it would show. A blank pane is routine on a running session -- `start`
# clears the pane after every auto-compaction, mid-turn -- and must not light up.
# A state the hooks publish that this script does not know is not its to guess.
add_bound_pane corr-blankbusy "" "" sid-blankbusy
add_bound_pane corr-newbusy compacting "" sid-newbusy

run_rows() {
  rm -f "$work/rows"
  tmux -L "$socket" run-shell \
    "cd $PWD && PATH=$work/stub:$PWD/bin:\$PATH tmux-agents --rows >$work/rows 2>$work/rows.err"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$work/rows" ] && return 0
    sleep 0.2
  done
  return 1
}

row_of() { grep -F "$1" "$work/rows" | head -1 | cut -f2-; }
rows_for() { grep -cF "$1" "$work/rows"; }

stub_claude '[{"sessionId":"sid-stale","status":"busy"},
              {"sessionId":"sid-needs","status":"busy"},
              {"sessionId":"sid-asking","status":"busy"},
              {"sessionId":"sid-late","status":"waiting","waitingFor":"permission prompt"},
              {"sessionId":"sid-unknown","status":"teleporting"},
              {"sessionId":"sid-shell","status":"shell"},
              {"sessionId":"sid-idle","status":"idle"},
              {"sessionId":"sid-running","status":"busy"},
              {"sessionId":"sid-shellbusy","status":"shell"},
              {"sessionId":"sid-blankbusy","status":"busy"},
              {"sessionId":"sid-newbusy","status":"busy"}]'

if ! run_rows; then
  fail "--rows produces a list" "stderr: $(cat "$work/rows.err" 2>/dev/null)"
else
  # The reported symptom: approving a long command leaves 🛑 up for as long as
  # the command runs, because the only hook that would clear it fires when the
  # tool finishes.
  case "$(row_of corr-stale)" in
    '▶ '*) pass "a session the CLI calls busy loses its stale 🛑" ;;
    *) fail "a session the CLI calls busy loses its stale 🛑" "row: $(row_of corr-stale)" ;;
  esac
  if [ "$(rows_for corr-stale)" = 1 ]; then
    pass "the contradicted per-actor listing is dropped, not re-rendered"
  else
    fail "the contradicted per-actor listing is dropped, not re-rendered" \
      "$(rows_for corr-stale) rows for one pane"
  fi

  case "$(row_of corr-needs)" in
    '▶ '*) pass "needs_input counts as blocked when deciding to correct" ;;
    *) fail "needs_input counts as blocked when deciding to correct" "row: $(row_of corr-needs)" ;;
  esac
  case "$(row_of corr-asking)" in
    '▶ '*) pass "asking counts as blocked when deciding to correct" ;;
    *) fail "asking counts as blocked when deciding to correct" "row: $(row_of corr-asking)" ;;
  esac

  # The other direction: the Notification that publishes 🛑 is 6s behind the
  # dialog, and the CLI is not.
  case "$(row_of corr-late)" in
    '🛑'*'permission prompt'*) pass "a dialog the hooks have not reported yet shows as blocked" ;;
    *) fail "a dialog the hooks have not reported yet shows as blocked" "row: $(row_of corr-late)" ;;
  esac

  # A status this script has never heard of is left alone rather than guessed
  # at. The vocabulary belongs to the CLI, and mapping an unknown one onto a
  # glyph would invent a state.
  case "$(row_of corr-unknown)" in
    '🛑'*) pass "an unrecognised status leaves the row alone" ;;
    *) fail "an unrecognised status leaves the row alone" "row: $(row_of corr-unknown)" ;;
  esac

  # `shell` is the fourth value the CLI publishes, and leaving it unrecognised
  # left a pane stuck red with no way back: the poller is the only thing that can
  # clear a state no hook reports, and it declined to. It is not a guess -- the
  # CLI derives it as `status === "idle" && <in a shell> ? "shell" : status`, so
  # it is idle with the user at a shell, and idle already means "not blocked".
  # Read out of the installed bundle (2.1.284), which is why the value is pinned
  # here rather than left to a comment.
  # The glyph is named rather than "anything but red", as the two cases above name
  # theirs: `shell` refines idle, so the row must land on stalled's 🟢 and not on
  # busy's ▶. A catch-all here passed a mutation mapping shell onto busy, which
  # only the pane-option case below caught -- and that goes through the hook's own
  # glyph_of, not the awk that renders this row.
  case "$(row_of corr-shell)" in
    '🟢'*) pass "a shell status renders as stalled, the idle it refines" ;;
    '') fail "a shell status renders as stalled, the idle it refines" "the row disappeared" ;;
    *) fail "a shell status renders as stalled, the idle it refines" \
      "row: $(row_of corr-shell)" ;;
  esac

  # The glyph is named in both: the pre-existing rule left these rows alone as
  # "both unblocked", so the hook's glyph surviving is the regression.
  case "$(row_of corr-idle)" in
    '🟢'*) pass "a session the CLI calls idle loses its stale ▶" ;;
    *) fail "a session the CLI calls idle loses its stale ▶" "row: $(row_of corr-idle)" ;;
  esac
  if [ "$(rows_for corr-idle)" = 1 ]; then
    pass "the interrupted subagent's ▶ row is dropped with the listing"
  else
    fail "the interrupted subagent's ▶ row is dropped with the listing" \
      "$(rows_for corr-idle) rows: $(grep -F corr-idle "$work/rows" | cut -f2- | tr '\n' '|')"
  fi
  case "$(row_of corr-running)" in
    '▶ '*) pass "a session the CLI calls busy loses its stale 🟢" ;;
    *) fail "a session the CLI calls busy loses its stale 🟢" "row: $(row_of corr-running)" ;;
  esac
  case "$(row_of corr-shellbusy)" in
    '🟢'*) pass "a busy pane whose session is at a shell goes green" ;;
    *) fail "a busy pane whose session is at a shell goes green" "row: $(row_of corr-shellbusy)" ;;
  esac
  if [ "$(rows_for corr-blankbusy)" = 0 ]; then
    pass "a blank pane on a running session gets no row"
  else
    fail "a blank pane on a running session gets no row" "row: $(row_of corr-blankbusy)"
  fi
  case "$(row_of corr-newbusy)" in
    '🟢'*) pass "a hook state this script does not know is not corrected to running" ;;
    *) fail "a hook state this script does not know is not corrected to running" \
      "row: $(row_of corr-newbusy)" ;;
  esac

  # A session that started before the binding existed has no id, and must stay
  # visible on what the hooks know rather than being treated as unknown.
  case "$(row_of corr-nobind)" in
    '🛑'*) pass "a pane with no session id keeps its hook state" ;;
    *) fail "a pane with no session id keeps its hook state" "row: $(row_of corr-nobind)" ;;
  esac

  case "$(row_of corr-gone)" in
    '🛑'*) pass "a session the CLI does not list keeps its hook state" ;;
    *) fail "a session the CLI does not list keeps its hook state" "row: $(row_of corr-gone)" ;;
  esac
fi

# A CLI that cannot answer degrades to the hook state. An indicator that
# vanishes when a CLI changes is worse than one that is late, and this is the
# path a future rename of `claude agents --json` would take.
stub_claude fail
if ! run_rows; then
  fail "--rows survives a CLI that fails" "stderr: $(cat "$work/rows.err" 2>/dev/null)"
else
  case "$(row_of corr-late)" in
    '▶ '*) pass "a failing CLI leaves every row as the hooks published it" ;;
    *) fail "a failing CLI leaves every row as the hooks published it" "row: $(row_of corr-late)" ;;
  esac
fi

# The quieter break: a CLI that exits 0 with something that is not JSON -- a
# changed output format, a warning on stdout. jq failing must degrade the same
# way, not turn into an empty correction map that the awk then applies.
stub_claude 'Warning: agents is now "claude sessions" {'
if ! run_rows; then
  fail "--rows survives a CLI that answers with non-JSON" "stderr: $(cat "$work/rows.err" 2>/dev/null)"
else
  case "$(row_of corr-late)" in
    '▶ '*) pass "non-JSON from the CLI leaves the rows as the hooks published them" ;;
    *) fail "non-JSON from the CLI leaves the rows as the hooks published them" "row: $(row_of corr-late)" ;;
  esac
fi

# When the two sides AGREE that a session is blocked, the hook's data is kept
# whole: its note names the tool, and its per-actor listing names which
# subagent is blocked -- the CLI knows neither. A correction that rewrote every
# bound row would replace both with the CLI's vaguer waitingFor.
add_bound_pane corr-agree waiting "Bash: rm -rf build" sid-agree
agree_pane=$(tmux -L "$socket" list-panes -t work:corr-agree -F '#{pane_id}' | head -1)
tmux -L "$socket" set-option -p -t "$agree_pane" @claude_agents \
  "waiting${US}${now}${US}Explore${US}Bash: rm -rf build${RS}busy${US}${now}${US}${US}${RS}"
# A state the hooks never published before, on a pane of its own: the list must
# show it rather than drop the pane, since a new state is still an agent.
add_bound_pane corr-newstate teleporting "" ""
stub_claude '[{"sessionId":"sid-agree","status":"waiting","waitingFor":"permission prompt"}]'
if ! run_rows; then
  fail "--rows produces a list (agreement case)" "stderr: $(cat "$work/rows.err" 2>/dev/null)"
else
  case "$(grep -F 'corr-agree [Explore]' "$work/rows" | head -1 | cut -f2-)" in
    '🛑'*'Bash: rm -rf build'*) pass "agreement keeps the hook's note and per-actor rows" ;;
    *) fail "agreement keeps the hook's note and per-actor rows" "rows: $(grep -F corr-agree "$work/rows" | cut -f2- | tr '\n' '|')" ;;
  esac
  if grep -F corr-agree "$work/rows" | grep -qF 'permission prompt'; then
    fail "and does not replace it with the CLI's waitingFor" "$(grep -F corr-agree "$work/rows" | cut -f2-)"
  else
    pass "and does not replace it with the CLI's waitingFor"
  fi
  if [ "$(rows_for corr-newstate)" -ge 1 ]; then
    pass "a state the script does not know is still listed"
  else
    fail "a state the script does not know is still listed" "no row for corr-newstate"
  fi
fi
tmux -L "$socket" kill-window -t work:corr-agree 2>/dev/null
tmux -L "$socket" kill-window -t work:corr-newstate 2>/dev/null

# The picker's FIRST list comes from the pane options alone: `claude agents
# --json` costs ~140ms, the whole latency budget before the popup paints, so it
# is paid on the first refresh instead. Bound panes exist at this point, so a
# picker that corrected up front would have every reason to call the CLI -- and
# the stub fzf exits before any refresh could, so any call here is the first
# list's.
cat >"$work/stub/claude" <<STUB
#!/bin/sh
echo called >>"$work/claude-first.log"
echo '[]'
STUB
chmod +x "$work/stub/claude"
rm -f "$work/claude-first.log"
if run_picker; then
  if [ -s "$work/claude-first.log" ]; then
    fail "the first list is drawn without running the CLI" \
      "$(wc -l <"$work/claude-first.log" | tr -d ' ') call(s)"
  else
    pass "the first list is drawn without running the CLI"
  fi
else
  fail "the first list is drawn without running the CLI" "fzf stub was never reached"
fi

# --- the same correction, written back onto the panes -------------------------

# --rows fixes the picker and nothing else: the WezTerm tab glyph is read from
# @claude_glyph by set-titles-string, so it stays wrong until something writes
# the option. --sync is that something, run from launchd, and it applies the
# SAME rule -- which is why it is a mode of this script rather than a second one
# that would drift from it.
#
# It writes through the hook's `correct` mode rather than setting the options
# itself, so what is asserted here is the end state of that whole path.

socket_path=$(tmux -L "$socket" display-message -p '#{socket_path}')
pane_of() { tmux -L "$socket" list-panes -t "work:$1" -F '#{pane_id}' | head -1; }
opt_of() { tmux -L "$socket" show-options -p -t "$(pane_of "$1")" -qv "$2"; }

# A bound pane the hooks have published nothing for. The CLI calls it idle, and
# nothing may appear on it: every idle Claude session on the machine lighting up
# is the failure mode a poller invites, and "agree = leave alone" is what
# prevents it.
add_bound_pane corr-blank "" "" sid-blank

# --sync calls the hook at $HOME/.claude/hooks/agent-state.sh, so the fixture is
# a $HOME rather than a variable pointing the script somewhere else: the script
# keeps no seam that exists only for this test, which is the same rule that kept
# fzf and ssh stubbed as programs on PATH.
mkdir -p "$work/home/.claude/hooks"
ln -sf "$PWD/root/.claude/hooks/agent-state.sh" "$work/home/.claude/hooks/agent-state.sh"

# $1, when given, replaces the hook with that program -- used by the cost cases,
# which count invocations rather than looking at what they did.
run_sync() {
  rm -f "$work/sync.err"
  if [ -n "${1:-}" ]; then
    ln -sf "$1" "$work/home/.claude/hooks/agent-state.sh"
  else
    ln -sf "$PWD/root/.claude/hooks/agent-state.sh" "$work/home/.claude/hooks/agent-state.sh"
  fi
  HOME="$work/home" \
    XDG_STATE_HOME="$work/state" \
    TMUX="$socket_path,0,0" \
    PATH="$work/stub:$PWD/bin:$PATH" \
    tmux-agents --sync 2>"$work/sync.err"
}

stub_claude '[{"sessionId":"sid-stale","status":"busy"},
              {"sessionId":"sid-needs","status":"busy"},
              {"sessionId":"sid-blank","status":"idle"},
              {"sessionId":"sid-late","status":"waiting","waitingFor":"permission prompt"},
              {"sessionId":"sid-unknown","status":"teleporting"},
              {"sessionId":"sid-shell","status":"shell"},
              {"sessionId":"sid-idle","status":"idle"},
              {"sessionId":"sid-running","status":"busy"},
              {"sessionId":"sid-shellbusy","status":"shell"},
              {"sessionId":"sid-blankbusy","status":"busy"},
              {"sessionId":"sid-newbusy","status":"busy"}]'

if ! run_sync; then
  fail "--sync runs" "stderr: $(cat "$work/sync.err" 2>/dev/null)"
else
  # The reported symptom, on the surface the user actually looks at.
  if [ "$(opt_of corr-stale @claude_state)" = busy ] &&
    [ "$(opt_of corr-stale @claude_glyph)" = '▶ ' ]; then
    pass "a stale 🛑 is cleared off the pane itself"
  else
    fail "a stale 🛑 is cleared off the pane itself" \
      "state: [$(opt_of corr-stale @claude_state)] glyph: [$(opt_of corr-stale @claude_glyph)]"
  fi

  if [ "$(opt_of corr-needs @claude_state)" = busy ]; then
    pass "a stale needs_input is cleared too"
  else
    fail "a stale needs_input is cleared too" "state: [$(opt_of corr-needs @claude_state)]"
  fi

  if [ "$(opt_of corr-late @claude_state)" = waiting ] &&
    [ "$(opt_of corr-late @claude_note)" = "permission prompt" ]; then
    pass "a dialog the hooks have not reported yet reaches the pane"
  else
    fail "a dialog the hooks have not reported yet reaches the pane" \
      "state: [$(opt_of corr-late @claude_state)] note: [$(opt_of corr-late @claude_note)]"
  fi

  # The pane, not just the picker's view: `shell` is where the poller is the only
  # thing that could ever clear the glyph, since no hook reports the transition
  # into it either.
  if [ "$(opt_of corr-shell @claude_state)" = stalled ]; then
    pass "a shell session's stale red is cleared off the pane too"
  else
    fail "a shell session's stale red is cleared off the pane too" \
      "state: [$(opt_of corr-shell @claude_state)]"
  fi

  # The reported symptom of the busy/idle half: a tab stuck at ▶ on an idle
  # session, for as long as the tab stayed open.
  if [ "$(opt_of corr-idle @claude_state)" = stalled ] &&
    [ "$(opt_of corr-idle @claude_glyph)" = '🟢' ]; then
    pass "a stale ▶ is cleared off the pane itself"
  else
    fail "a stale ▶ is cleared off the pane itself" \
      "state: [$(opt_of corr-idle @claude_state)] glyph: [$(opt_of corr-idle @claude_glyph)]"
  fi
  if [ "$(opt_of corr-running @claude_state)" = busy ]; then
    pass "a running session's stale 🟢 is replaced on the pane"
  else
    fail "a running session's stale 🟢 is replaced on the pane" \
      "state: [$(opt_of corr-running @claude_state)]"
  fi
  if [ "$(opt_of corr-shellbusy @claude_state)" = stalled ]; then
    pass "a busy pane whose session is at a shell is set to stalled"
  else
    fail "a busy pane whose session is at a shell is set to stalled" \
      "state: [$(opt_of corr-shellbusy @claude_state)]"
  fi
  if [ -z "$(opt_of corr-blankbusy @claude_state)" ]; then
    pass "a blank pane on a running session stays blank"
  else
    fail "a blank pane on a running session stays blank" \
      "state: [$(opt_of corr-blankbusy @claude_state)]"
  fi
  if [ "$(opt_of corr-newbusy @claude_state)" = compacting ]; then
    pass "a hook state this script does not know is left on the pane"
  else
    fail "a hook state this script does not know is left on the pane" \
      "state: [$(opt_of corr-newbusy @claude_state)]"
  fi

  if [ -z "$(opt_of corr-blank @claude_state)" ]; then
    pass "an idle session with nothing published stays blank"
  else
    fail "an idle session with nothing published stays blank" \
      "state: [$(opt_of corr-blank @claude_state)]"
  fi

  for w in corr-unknown corr-nobind corr-gone; do
    if [ "$(opt_of "$w" @claude_state)" = waiting ]; then
      pass "$w is left as the hooks published it"
    else
      fail "$w is left as the hooks published it" "state: [$(opt_of "$w" @claude_state)]"
    fi
  done
fi

# The binding is the join key, and it has to outlive every correction: losing it
# would make the pane permanently uncorrectable, which no glyph would show.
if [ "$(opt_of corr-stale @claude_session_id)" = sid-stale ]; then
  pass "a correction leaves @claude_session_id bound"
else
  fail "a correction leaves @claude_session_id bound" \
    "binding: [$(opt_of corr-stale @claude_session_id)]"
fi

# The per-actor listing has to be corrected on the pane too, not just the
# aggregate. `--rows` drops a contradicted listing rather than re-rendering it,
# but that is the picker's own view; the option left on the pane is what the NEXT
# reader sees -- another picker, a refresh, `prefix + A` counting reds off the tab
# titles. A pane whose @claude_state says busy while @claude_agents still holds a
# waiting record is a pane that goes red again the moment anything expands the
# listing, and nothing here noticed that until this case.
#
# Asserted in both directions, because "no longer says waiting" is also what an
# empty option says, and clearing the listing would be a different bug wearing
# the same result.
#
# What this case CAN see is the end state of the option: the correction is
# republished, and the waiting record is not in it. It cannot see the hook's
# unblock_actors at work. The fixture wrote @claude_agents with set-option, so
# the hook's own record store never held the waiting Explore record, and the
# republish comes out clean whether or not that function ran. Turning a stale
# record in the STORE into busy is pinned by agent-state.test.sh, which drives
# the hook through its events.
stale_listing=$(opt_of corr-stale @claude_agents)
case $stale_listing in
  *waiting*)
    fail "a corrected pane's republished listing holds no blocked record" \
      "listing: [$stale_listing]"
    ;;
  *busy*) pass "a corrected pane's republished listing holds no blocked record" ;;
  *)
    fail "a corrected pane's republished listing holds no blocked record" \
      "the listing was cleared rather than rebuilt: [$stale_listing]"
    ;;
esac

# Idempotent: the second pass agrees with the CLI everywhere, so it must find
# nothing to do. A poller that rewrites the same options every tick would also
# call `refresh-client -S` every tick, forever.
before=$(tmux -L "$socket" list-panes -a -F '#{pane_id} #{@claude_state} #{@claude_since}')
run_sync
if [ "$before" = "$(tmux -L "$socket" list-panes -a -F '#{pane_id} #{@claude_state} #{@claude_since}')" ]; then
  pass "a second pass changes nothing"
else
  fail "a second pass changes nothing" "the options moved on a no-op pass"
fi

# Cost, not output. A pane the CLI agrees with must not be written to at all,
# and no assertion above can tell the difference: re-applying a state a pane
# already holds is a no-op by the time it reaches the options, because the hook
# short-circuits on its own last-published record. What it is NOT free of is the
# process -- one per pane, every tick, forever -- and dropping the comparison
# that produces `changes` is therefore invisible except here.
cat >"$work/stub/hook" <<STUB
#!/bin/sh
printf '%s %s\n' "\$TMUX_PANE" "\$2" >>"$work/hook.log"
STUB
chmod +x "$work/stub/hook"
rm -f "$work/hook.log"
touch "$work/hook.log"
run_sync "$work/stub/hook"
called=$(grep -c . "$work/hook.log")
# Nothing is wrong any more -- the panes were corrected above -- so the CLI now
# agrees with every one of them.
if [ "$called" -eq 0 ]; then
  pass "a tick with nothing to correct spawns no hook at all"
else
  fail "a tick with nothing to correct spawns no hook at all" \
    "$called calls: $(tr '\n' ' ' <"$work/hook.log")"
fi

# ...and the panes that DO disagree are the only ones it reaches. Rewinding one
# pane to a stale 🛑 is enough to show both halves at once.
tmux -L "$socket" set-option -p -t "$(pane_of corr-stale)" @claude_state waiting
rm -f "$work/hook.log"
touch "$work/hook.log"
run_sync "$work/stub/hook"
if [ "$(cat "$work/hook.log")" = "$(pane_of corr-stale) busy" ]; then
  pass "only the pane that disagrees is written to"
else
  fail "only the pane that disagrees is written to" \
    "log: [$(tr '\n' ' ' <"$work/hook.log" 2>/dev/null)]"
fi
rm -f "$work/stub/hook"
run_sync

# launchd starts the job with no LANG, LC_ALL or LC_CTYPE and no $TMUX, and a
# tmux client with neither prints every control character in a -F format as `_`
# -- the TAB separators included. The whole listing then parses as one field per
# row, no pane appears bound to a session, and the tick returns early having
# corrected nothing: green picker, red tab, exit 0, empty log.
#
# BOTH have to be missing, which is why every case above is blind to it: a
# client that finds $TMUX set assumes UTF-8 whatever the locale says, and
# run_sync sets $TMUX to reach this suite's server. So this case runs against a
# bare_tmux server, which a client with no $TMUX finds on its own -- exactly how
# the launchd job finds the real one.
#
# Everything else it needs is its own too -- $HOME with the real hook, state
# dir, CLI stub -- so it holds wherever it sits in this file: the shared ones
# are rewired by the cases around it.
lt_dir="$work/launchd-tmpdir"
mkdir -p "$lt_dir" "$work/lt-home/.claude/hooks" "$work/lt-stub"
ln -sf "$PWD/root/.claude/hooks/agent-state.sh" "$work/lt-home/.claude/hooks/agent-state.sh"
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"sid-launchd\",\"status\":\"busy\"}]'" \
  >"$work/lt-stub/claude"
chmod +x "$work/lt-stub/claude"
bare_tmux "$lt_dir" -f /dev/null new-session -d -s launchd "$IDLE"
lt_sock=$(bare_tmux "$lt_dir" display-message -p '#{socket_path}')
lt_pane=$(bare_tmux "$lt_dir" list-panes -t launchd -F '#{pane_id}' | head -1)
bare_tmux "$lt_dir" set-option -p -t "$lt_pane" @claude_session_id sid-launchd
lt_opt() { bare_tmux "$lt_dir" show-options -p -t "$lt_pane" -qv "$1"; }
# Published through the hook, not with set-option: an option written behind the
# hook's back leaves its records matching `.published`, so the correction would
# derive nothing new and skip the very write asserted here.
HOME="$work/lt-home" XDG_STATE_HOME="$work/lt-state" \
  TMUX="$lt_sock,0,0" TMUX_PANE="$lt_pane" \
  "$PWD/root/.claude/hooks/agent-state.sh" correct waiting "permission prompt"
# Without this the case passes vacuously whenever the setup fails to publish,
# since "busy afterwards" is also what an untouched pane says.
if [ "$(lt_opt @claude_state)" != waiting ]; then
  fail "a stale 🛑 is cleared with no locale and no \$TMUX, as under launchd" \
    "setup did not publish waiting: [$(lt_opt @claude_state)]"
elif ! env -u TMUX -u LANG -u LC_ALL -u LC_CTYPE \
  TMUX_TMPDIR="$lt_dir" \
  HOME="$work/lt-home" \
  XDG_STATE_HOME="$work/lt-state" \
  PATH="$work/lt-stub:$PWD/bin:$PATH" \
  tmux-agents --sync 2>"$work/sync.err"; then
  fail "--sync runs with no locale and no \$TMUX" "stderr: $(cat "$work/sync.err" 2>/dev/null)"
# The glyph as well as the state: @claude_glyph is what set-titles-string puts
# on the tab, which is where the symptom was seen.
elif [ "$(lt_opt @claude_state)" = busy ] && [ "$(lt_opt @claude_glyph)" = '▶ ' ]; then
  pass "a stale 🛑 is cleared with no locale and no \$TMUX, as under launchd"
else
  fail "a stale 🛑 is cleared with no locale and no \$TMUX, as under launchd" \
    "state: [$(lt_opt @claude_state)] glyph: [$(lt_opt @claude_glyph)]"
fi
bare_tmux "$lt_dir" kill-server 2>/dev/null

# A background timer may not open an ssh connection, and `collect_rows local` is
# the only thing stopping it. Without this the guarantee is untested: the remote
# fixtures live further down the file, so at this point there is no @ssh_my_machine
# pane for a missing `local` to fan out to, and dropping the argument would pass
# every other case here.
tmux -L "$socket" new-window -t work -n sync-ssh "$IDLE"
sync_ssh_pane=$(pane_of sync-ssh)
tmux -L "$socket" set-option -p -t "$sync_ssh_pane" @ssh_my_machine 1
tmux -L "$socket" set-option -p -t "$sync_ssh_pane" @ssh_host somehost
cat >"$work/stub/ssh" <<STUB
#!/bin/sh
echo "\$@" >>"$work/ssh.log"
STUB
chmod +x "$work/stub/ssh"
rm -f "$work/ssh.log"
run_sync
if [ ! -s "$work/ssh.log" ]; then
  pass "a sync pass never opens an ssh connection"
else
  fail "a sync pass never opens an ssh connection" "$(cat "$work/ssh.log")"
fi
rm -f "$work/stub/ssh"
tmux -L "$socket" kill-window -t work:sync-ssh 2>/dev/null

# A CLI that cannot answer must leave every pane exactly as it is, for the same
# reason --rows degrades to the hook state: an indicator that vanishes when a
# CLI is renamed is worse than one that is late.
stub_claude fail
before=$(tmux -L "$socket" list-panes -a -F '#{pane_id} #{@claude_state}')
if ! run_sync; then
  fail "--sync survives a CLI that fails" "stderr: $(cat "$work/sync.err" 2>/dev/null)"
elif [ "$before" = "$(tmux -L "$socket" list-panes -a -F '#{pane_id} #{@claude_state}')" ]; then
  pass "a failing CLI leaves every pane untouched"
else
  fail "a failing CLI leaves every pane untouched" "the options moved"
fi

tmux -L "$socket" kill-window -t work:corr-blank 2>/dev/null
for w in corr-stale corr-late corr-needs corr-asking corr-unknown corr-shell corr-nobind corr-gone corr-idle corr-running corr-shellbusy corr-blankbusy corr-newbusy; do
  tmux -L "$socket" kill-window -t "work:$w" 2>/dev/null
done

# With the bound panes gone, no pane on this server carries a session id -- and
# that is the guard which makes a 5-second timer affordable, since `claude
# agents --json` is the only expensive part of a tick. Asserted here because the
# fixtures have just been removed, and asserted at all because nothing about the
# result differs: the CLI would simply be asked a question with no use for the
# answer.
cat >"$work/stub/claude" <<STUB
#!/bin/sh
echo called >>"$work/claude.log"
echo '[]'
STUB
chmod +x "$work/stub/claude"
rm -f "$work/claude.log"
run_sync
if [ ! -s "$work/claude.log" ]; then
  pass "a tick with no pane bound to a session does not run the CLI"
else
  fail "a tick with no pane bound to a session does not run the CLI" \
    "$(wc -l <"$work/claude.log") calls"
fi
rm -f "$work/stub/claude"

# The state a launchd job spends most of its life in: tmux is not running at
# all. It must exit 0 and say nothing, or the log named in the plist grows by a
# line every five seconds forever.
sync_out=$(HOME="$work/home" XDG_STATE_HOME="$work/state" \
  TMUX="$work/no-such-socket,0,0" PATH="$work/stub:$PWD/bin:$PATH" \
  tmux-agents --sync 2>&1)
sync_status=$?
if [ "$sync_status" -eq 0 ] && [ -z "$sync_out" ]; then
  pass "a tick with no tmux server at all is silent and succeeds"
else
  fail "a tick with no tmux server at all is silent and succeeds" \
    "exit $sync_status, output: [$sync_out]"
fi

# --- remote hosts -------------------------------------------------------------

fresh_server

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
printf '%s\n' "\$@" >"$work/ssh-argv"
for a in "\$@"; do cmd=\$a; done
echo "\$cmd" >>"$work/ssh-calls"
fmt=\${cmd#*-F \'}
prefix=\${fmt%%#\{*}
printf '%s%s\t@9\t%%9\tremote-win\tasking\t%s\tremote note\n' "\$prefix" remote-sess $((now - 900))
# A second remote pane, running subagents. The per-actor listing has to survive
# the format expansion done by the *remote* tmux and the ssh transport, which is
# the one thing no local case can check -- and its separators are control
# characters, so a transport that scrubbed them would fail here and nowhere else.
# The separators live in the *format*, never in an argument: printf expands
# escapes in the format string only, so a '\037' passed as %s arrives as four
# literal characters and the record silently keeps its separator as text.
printf '%s%s\t@8\t%%8\tremote-multi\twaiting\t%s\tremote block\tbusy\037%s\037\037\036waiting\037%s\037Explore\037remote block\036\n' \\
  "\$prefix" remote-sess $((now - 120)) $((now - 60)) $((now - 120))
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

  # The per-actor listing over ssh. Its separators are control characters, so
  # this is also the only case that would notice a transport scrubbing them.
  multi_rows=$(cut -f2- "$work/list" | grep -c 'remote-multi' || true)
  if [ "$multi_rows" = 2 ]; then
    pass "a remote pane's actors are expanded into a row each"
  else
    fail "a remote pane's actors are expanded into a row each" "got $multi_rows row(s)" \
      "$(cut -f2- "$work/list" | grep 'remote-multi')"
  fi
  remote_agent_row=$(cut -f2- "$work/list" | grep 'remote-multi \[Explore\]' | head -1)
  case "$remote_agent_row" in
    '🛑 '*bakery*'remote block'*)
      pass "the remote subagent keeps its glyph, host and note"
      ;;
    *) fail "the remote subagent keeps its glyph, host and note" \
      "row: ${remote_agent_row:-<missing>}" ;;
  esac

  calls=$(wc -l <"$work/ssh-calls" | tr -d ' ')
  if [ "$calls" = 1 ]; then
    pass "two panes on one host are queried once, not twice"
  else
    fail "two panes on one host are queried once, not twice" "ssh ran $calls time(s)"
  fi

  # The bounds the picker's latency depends on. tmux-agents.md counts on a host
  # that is asleep costing at most ConnectTimeout, and on no prompt ever being
  # able to block the popup (BatchMode); the socket must be this script's own,
  # never myssh's. The stub fails at once, so none of this is otherwise seen.
  for opt in BatchMode=yes ConnectTimeout=3 "ControlPath=$HOME/.ssh/cm-agents-%r@%h:%p"; do
    if grep -qxF -- "$opt" "$work/ssh-argv"; then
      pass "the remote query runs with $opt"
    else
      fail "the remote query runs with $opt" "argv: [$(tr '\n' ' ' <"$work/ssh-argv")]"
    fi
  done
else
  fail "the remote path produces a list" "fzf stub was never reached"
fi

# --rows is what the picker shows from its first refresh on: `start:reload`
# replaces the first list almost at once. It has to carry the remote rows too,
# or remote agents appear for a moment and vanish -- with every case above,
# which reads only that first list, still green.
if run_rows; then
  case "$(grep 'remote-win' "$work/rows" | cut -f2-)" in
    *bakery*) pass "the refreshed list keeps the remote rows" ;;
    *) fail "the refreshed list keeps the remote rows" "rows: $(cut -f2- "$work/rows" | tr '\n' '|')" ;;
  esac
else
  fail "the refreshed list keeps the remote rows" "--rows produced nothing: $(cat "$work/rows.err" 2>/dev/null)"
fi

# The `-u` on the remote command, which the stub above cannot see: it never runs
# the remote tmux, so dropping the flag passed every case. An ssh exec is the
# other place the launchd bug lives -- sshd starts the command with no $TMUX,
# and with a locale only if SendEnv and AcceptEnv happen to agree -- and there
# the failure is the quiet kind again: every remote row parses as one field and
# is dropped, so remote agents are simply gone. This stub runs the command for
# real, against a bare_tmux server, with the locale stripped.
rt_dir="$work/remote-tmpdir"
mkdir -p "$rt_dir"
bare_tmux "$rt_dir" -f /dev/null new-session -d -s far -n bare-remote-win "$IDLE"
rt_pane=$(bare_tmux "$rt_dir" list-panes -t far -F '#{pane_id}' | head -1)
bare_tmux "$rt_dir" set-option -p -t "$rt_pane" @claude_state asking
bare_tmux "$rt_dir" set-option -p -t "$rt_pane" @claude_since "$now"
cat >"$work/stub/ssh" <<STUB
#!/bin/sh
for a in "\$@"; do cmd=\$a; done
exec env -u TMUX -u LANG -u LC_ALL -u LC_CTYPE TMUX_TMPDIR="$rt_dir" sh -c "\$cmd"
STUB
chmod +x "$work/stub/ssh"
if run_picker; then
  bare_row=$(cut -f2- "$work/list" | grep 'bare-remote-win' || true)
  case "$bare_row" in
    '🛑 '*bakery*) pass "a remote agent is listed when the remote shell has no locale" ;;
    *) fail "a remote agent is listed when the remote shell has no locale" \
      "row: ${bare_row:-<missing>}" ;;
  esac
else
  fail "a remote agent is listed when the remote shell has no locale" "fzf stub was never reached"
fi
bare_tmux "$rt_dir" kill-server 2>/dev/null

# Which hosts are asked at all. @ssh_my_machine marks a myssh pane -- a machine
# running these dotfiles, with a tmux this script can query. A pane that is
# merely ssh'd somewhere carries @ssh_host alone, and querying it would open a
# connection to a machine with no such tmux, on every picker open.
tmux -L "$socket" new-window -t work -n ssh-plain "$IDLE"
plain_ssh_pane=$(tmux -L "$socket" list-panes -t work:ssh-plain -F '#{pane_id}' | head -1)
tmux -L "$socket" set-option -p -t "$plain_ssh_pane" @ssh_host plainhost
# And a myssh host that does not answer: ssh failing outright, as it does for a
# host that is asleep. Its rows are absent; everything local must still be there.
cat >"$work/stub/ssh" <<STUB
#!/bin/sh
echo "\$@" >>"$work/ssh-calls"
exit 255
STUB
chmod +x "$work/stub/ssh"
: >"$work/ssh-calls"
if run_picker; then
  if grep -q plainhost "$work/ssh-calls"; then
    fail "a pane ssh'd somewhere without myssh is never queried" "$(cat "$work/ssh-calls")"
  else
    pass "a pane ssh'd somewhere without myssh is never queried"
  fi
  if grep -q bakery "$work/ssh-calls"; then
    pass "while a myssh host is"
  else
    fail "while a myssh host is" "ssh calls: [$(tr '\n' '|' <"$work/ssh-calls")]"
  fi
  if cut -f2- "$work/list" | grep -q 'waiting-old'; then
    pass "an unreachable host leaves the local rows in place"
  else
    fail "an unreachable host leaves the local rows in place" "$(cut -f2- "$work/list")"
  fi
else
  fail "an unreachable host leaves the local rows in place" "fzf stub was never reached"
fi
rm -f "$work/stub/ssh"

# --- what the picked row turns into -------------------------------------------

fresh_server

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
#
# No client shows the agent's window on this throwaway server, so this is the
# "nothing is showing that window" refusal -- the "no WezTerm tab" one, with a
# client but no tab, is driven through the real fzf further down. The refusal
# is waited for in the server's command log, so the case cannot pass for a
# script that died before deciding anything.
nothing_said() {
  tmux -L "$socket" show-messages 2>/dev/null | grep -F 'display-message' |
    grep -cF 'nothing is showing that window' || true
}
said_before=$(nothing_said)
stub_pick ''
select_first
tmux -L "$socket" run-shell "cd $PWD && PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/out 2>&1"
for _ in $(seq 1 100); do
  [ "$(nothing_said)" -gt "$said_before" ] && break
  sleep 0.05
done
if [ "$(nothing_said)" -gt "$said_before" ]; then
  pass "enter on a window no client shows says so"
else
  fail "enter on a window no client shows says so" "$(cat "$work/out" 2>/dev/null)"
fi
if [ "$(active_pane)" = "$other_pane" ]; then
  pass "enter on a window no client shows leaves the agent's window alone"
else
  fail "enter on a window no client shows leaves the agent's window alone" \
    "active pane moved to $(active_pane)" "$(cat "$work/out" 2>/dev/null)"
fi

# ctrl-o needs a client to open a popup on, and a throwaway server has none.
# Refusing must then do NOTHING -- in particular it must not fall back to the
# jump. The two keys mean different things, and a ctrl-o that quietly moved you
# to another tab is worse than one that does not fire.
stub_pick 'ctrl-o'
select_first
# No wait after it: run-shell without -b returns only once tmux-agents has
# exited, and a jump is a select-pane it would have made before that. (The one
# thing it starts in the background is the view, which needs a client.)
tmux -L "$socket" run-shell "cd $PWD && PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/out 2>&1"
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
fresh_server bare
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
  #
  # TERM is supplied, and unconditionally. A GitHub runner provides none, and
  # tmux then refuses the pty outright -- "open terminal failed: terminal does
  # not support clear" -- which reaches the test only as a client that never
  # appears and a timeout after the wait loop. Reproduced in an ubuntu:24.04
  # container: identical failure with TERM unset, green with it set. The value is
  # not a property of the developer's terminal, because the client being attached
  # is tmux's own and not theirs.
  if [ "${OSTYPE:-}" != "${OSTYPE#darwin}" ]; then
    { sleep 120 | env -u TMUX -u SSH_CONNECTION TERM=xterm-256color script -q /dev/null tmux -L "$socket" attach -t "$1"; } >"$work/pty.log" 2>&1 &
  else
    { sleep 120 | env -u TMUX -u SSH_CONNECTION TERM=xterm-256color script -q -c "tmux -L $socket attach -t $1" /dev/null; } >"$work/pty.log" 2>&1 &
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
  for _ in $(seq 1 120); do
    client=$(tmux -L "$socket" list-clients -F '#{client_name}' | head -1)
    [ -n "$client" ] && break
    sleep 0.05
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

  # No sleep after the key. display-popup run from the command line returns only
  # once the popup's command has exited (measured on 3.7c: a 1.5s command held
  # it 1.6s), so tmux-agents is done when this returns and the next press finds
  # no popup open -- which matters, because a second display-popup on a client
  # that shows one is dropped without a word. What is NOT done on return is a
  # view tmux-agents started with `run-shell -b`; a case asserting that no view
  # opened has to allow for that itself (no_view_after).
  press_ctrl_o() {
    tmux -L "$socket" display-popup -c "$client" -E -w 60 -h 20 \
      "sh -c 'PICK=$1 PATH=$work/stub:$PWD/bin:\$PATH tmux-agents >$work/out 2>&1'"
  }
  # What the key said, read out of the server's command log -- which records
  # every command with its arguments, `display-message "..."` included. This is
  # the only observable the refusals have: msg() writes to a status line that
  # nothing headless can capture, and a case asserting merely "no view opened"
  # would pass just as well for a script that died on line one.
  #
  # Server-wide and not `-t "$client"`: the per-client log holds only what was
  # actually rendered on that client's status line, which depends on it being
  # attached and on the message not having been superseded. The command log
  # answers the question the test is really asking -- which branch ran.
  msg_log() { tmux -L "$socket" show-messages 2>/dev/null | grep -F 'display-message'; }
  said_count() { msg_log | grep -cF "$1" || true; }
  # wait_said <count before> <sentence> — wait for the sentence to be logged
  # once more than it had been. Its mere presence proves nothing: two prefix + A
  # cases refuse with the same sentence, so the second was satisfied by the
  # first one's line whether or not its own run got as far as deciding. What it
  # settles is WHICH branch ran, and an absence the script would have produced
  # before logging. It does not settle "no view opened": the line is logged
  # before the point a missing `exit 0` would fall through to opening one in
  # the background -- that is no_view_after's fixed window, below.
  wait_said() {
    for _ in $(seq 1 100); do
      [ "$(said_count "$2")" -gt "$1" ] && return 0
      sleep 0.05
    done
    return 1
  }
  # A mirror is open once a CLIENT is attached to it, not once its session
  # exists. tmux-agent-view creates the session and attaches after, and under
  # load that gap outlasted the check: a case read the clients, found none ("the
  # view is showing []"), and the late attach then outlived drop_mirrors and
  # failed the next case as well. Pinned by delaying that attach by 3s, which
  # failed four cases here before this and none after.
  wait_mirror() {
    for _ in $(seq 1 100); do
      tmux -L "$socket" list-clients -F '#{client_session}' | grep -q '^_agent_' && return 0
      sleep 0.05
    done
    return 1
  }
  # no_view_after -- succeed when no mirror exists after a fixed window. The
  # refusal is logged BEFORE the point where a missing `exit 0` would fall
  # through to `run-shell -b ... open`, so its line in the log cannot decide
  # this, and a correct run produces no later event to wait for. Reading at
  # once let both cases below pass with that `exit 0` deleted; the window is
  # the honest remainder (bin/testing.md, rule 1).
  no_view_after() {
    sleep 1
    [ "$(mirrors)" = 0 ]
  }
  refused=$(said_count "that session is not waiting on you")
  press_ctrl_o busy-win
  if wait_said "$refused" "that session is not waiting on you" && no_view_after; then
    pass "ctrl-o on a session that is not blocked attaches nothing"
  else
    fail "ctrl-o on a session that is not blocked attaches nothing" \
      "sessions: $(tmux -L "$socket" list-sessions -F '#{session_name}' | tr '\n' ' ')" \
      "messages: $(msg_log | tail -3 | tr "\n" "|")"
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

  # The check after the picker, on a REMOTE blocked row. The binding refuses such
  # a row inside fzf, so this half is reached only if a future fzf ignored that,
  # and it has to hold on its own. Only here, with a client, is a missing refusal
  # visible: the view would open on whichever LOCAL window carries the remote
  # row's ids -- so the row is given ask-win's own ids to make that the outcome.
  # The stub reads its stdin first: left unread, the script's printf into it can
  # die of SIGPIPE, and pipefail then ends the run before the check is reached.
  ask_win_id=$(tmux -L "$socket" list-windows -t tabB -F '#{window_name} #{window_id}' |
    awk '$1 == "ask-win" { print $2 }')
  ask_pane_id=$(tmux -L "$socket" list-panes -t tabB:ask-win -F '#{pane_id}' | head -1)
  cp "$work/stub/fzf" "$work/fzf.pick"
  cat >"$work/stub/fzf" <<STUB
#!/bin/sh
cat >/dev/null
printf 'ctrl-o\n%s\t%s\n' "bakery|$ask_win_id|$ask_pane_id|asking" "remote row"
exit 0
STUB
  refused=$(said_count "answering a remote agent here is not supported yet")
  press_ctrl_o unused
  if wait_said "$refused" "answering a remote agent here is not supported yet" &&
    no_view_after; then
    pass "ctrl-o on a remote row that got past the picker is still refused"
  else
    fail "ctrl-o on a remote row that got past the picker is still refused" \
      "sessions: $(tmux -L "$socket" list-sessions -F '#{session_name}' | tr '\n' ' ')" \
      "messages: $(msg_log | tail -3 | tr "\n" "|")" \
      "$(cat "$work/out" 2>/dev/null)"
  fi
  cp "$work/fzf.pick" "$work/stub/fzf"

  press_ctrl_o ask-win
  wait_mirror
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

  # --- prefix + A, the picker-less path ----------------------------------------
  #
  # Same end state as ctrl-o, reached with no list drawn and nothing picked, so
  # the only thing standing between the key and the wrong agent is the awk that
  # chooses the row. Every way that can be wrong is silent: choose a busy row
  # and the view opens on an agent that is not blocked, choose none and the key
  # is dead, choose a remote one and display-popup is handed a window id from
  # another server. So the assertions are on WHICH window the mirror is showing,
  # never merely that one exists.
  #
  # It runs through `run-shell` rather than a popup because that is how the
  # binding runs it -- and that is the half that needs a client passed in, since
  # a run-shell child's $TMUX names the server and not the client that pressed
  # the key.
  # Detaching a mirror is asynchronous -- the popup, its client and its session
  # all go away after the detach returns -- so this WAITS for the count to reach
  # zero. Without the wait, the first case below inherits the mirror the ctrl-o
  # cases left on ask-win: wait_mirror returns instantly and the window name is
  # already the one the assertion expects, so the case passes in full without
  # --answer-first having run at all. The detach is repeated inside the wait,
  # because a mirror whose attach is still on its way has no client to detach
  # yet; detaching once and waiting left exactly that one behind.
  drop_mirrors() {
    for _ in $(seq 1 100); do
      for m in $(tmux -L "$socket" list-clients -F '#{client_name} #{client_session}' |
        awk '$2 ~ /^_agent_/ { print $1 }'); do
        tmux -L "$socket" detach-client -t "$m" 2>/dev/null
      done
      [ "$(mirrors)" = 0 ] && return 0
      sleep 0.05
    done
    return 1
  }
  # answer_first [extra PATH entry] — what the binding runs, with the client
  # passed in the way `run-shell` lets the binding pass it.
  answer_first() {
    tmux -L "$socket" run-shell -b \
      "cd $PWD && PATH=${1:+$1:}$PWD/bin:\$PATH tmux-agents --answer-first $client >$work/first 2>&1"
  }
  if ! drop_mirrors; then
    fail "the ctrl-o mirror is gone before prefix + A is tested" \
      "$(tmux -L "$socket" list-sessions -F '#{session_name}')"
  fi

  # tabB holds one busy window and one asking window. Only the second may be
  # opened, and the mirror's current window is what says which one it picked.
  answer_first
  if wait_mirror; then
    shown=$(tmux -L "$socket" list-clients -F '#{client_session} #{window_name}' |
      awk '$1 ~ /^_agent_/ { print $2; exit }')
    if [ "$shown" = ask-win ]; then
      pass "prefix + A opens the view on the blocked agent, not the busy one"
    else
      fail "prefix + A opens the view on the blocked agent, not the busy one" \
        "the view is showing [$shown]"
    fi
  else
    fail "prefix + A opens the view on the blocked agent, not the busy one" \
      "no mirror session appeared" "$(cat "$work/first" 2>/dev/null)"
  fi
  drop_mirrors

  # With nothing blocked it must open nothing at all. A key that falls back to
  # "the most interesting row" would take you to a busy agent you were not
  # asking about, which is the same mistake the picker's ctrl-o refuses to make.
  ask_pane=$(tmux -L "$socket" list-panes -t tabB:ask-win -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -pu -t "$ask_pane" @claude_state
  refused=$(said_count "nothing is waiting on you")
  answer_first
  if wait_said "$refused" "nothing is waiting on you" && [ "$(mirrors)" = 0 ]; then
    pass "prefix + A opens nothing when no agent is blocked, and says so"
  else
    fail "prefix + A opens nothing when no agent is blocked, and says so" \
      "sessions: $(tmux -L "$socket" list-sessions -F '#{session_name}' | tr '\n' ' ')" \
      "messages: $(msg_log | head -3 | tr "\n" "|")" \
      "$(cat "$work/first" 2>/dev/null)"
  fi
  drop_mirrors

  # prefix + A picks from the CORRECTED list. Picking from the raw pane options
  # would send it to a session that has already been answered -- and, in the
  # other direction, make it report "nothing is waiting on you" while a dialog
  # whose 🛑 is still 6s away sits open. The picker was taught this; the key
  # that skips the picker has to agree with it, or the two drift.
  stub_claude '[{"sessionId":"sid-answered","status":"busy"}]'
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_state asking
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_since "$now"
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_session_id sid-answered
  refused=$(said_count "nothing is waiting on you")
  answer_first "$work/stub"
  if wait_said "$refused" "nothing is waiting on you" && [ "$(mirrors)" = 0 ]; then
    pass "prefix + A ignores a red the session itself says is gone"
  else
    fail "prefix + A ignores a red the session itself says is gone" \
      "sessions: $(tmux -L "$socket" list-sessions -F '#{session_name}' | tr '\n' ' ')" \
      "messages: $(msg_log | head -3 | tr "\n" "|")" \
      "$(cat "$work/first" 2>/dev/null)"
  fi
  drop_mirrors
  rm -f "$work/stub/claude"
  tmux -L "$socket" set-option -pu -t "$ask_pane" @claude_session_id
  tmux -L "$socket" set-option -pu -t "$ask_pane" @claude_state

  # needs_input is the third blocked state and the one this key is likeliest to
  # lose: it ranks below asking/waiting, so every case above still passes with
  # it missing from the rule that picks the row. Alone, it must still be opened.
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_state needs_input
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_since "$now"
  answer_first
  if wait_mirror; then
    shown=$(tmux -L "$socket" list-clients -F '#{client_session} #{window_name}' |
      awk '$1 ~ /^_agent_/ { print $2; exit }')
    if [ "$shown" = ask-win ]; then
      pass "prefix + A opens the view on a needs_input agent too"
    else
      fail "prefix + A opens the view on a needs_input agent too" \
        "the view is showing [$shown]"
    fi
  else
    fail "prefix + A opens the view on a needs_input agent too" \
      "no mirror session appeared" "$(cat "$work/first" 2>/dev/null)"
  fi
  drop_mirrors

  # Several blocked at once: A answers the one blocked longest, whatever kind of
  # block it is -- needs_input shares the top rank with asking. Every case above
  # has exactly one local blocked row, so a pick that kept going and took the
  # LAST blocked row -- the newest -- would pass them all. The asking row is the
  # newer one, and was the pick back when needs_input ranked below it.
  tmux -L "$socket" new-window -t tabB -n need-win "$IDLE"
  need_pane=$(tmux -L "$socket" list-panes -t tabB:need-win -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$need_pane" @claude_state needs_input
  tmux -L "$socket" set-option -p -t "$need_pane" @claude_since $((now - 3600))
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_state asking
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_since "$now"
  answer_first
  if wait_mirror; then
    shown=$(tmux -L "$socket" list-clients -F '#{client_session} #{window_name}' |
      awk '$1 ~ /^_agent_/ { print $2; exit }')
    if [ "$shown" = need-win ]; then
      pass "prefix + A answers the longest-blocked of several, needs_input included"
    else
      fail "prefix + A answers the longest-blocked of several, needs_input included" \
        "the view is showing [$shown]"
    fi
  else
    fail "prefix + A answers the longest-blocked of several, needs_input included" \
      "no mirror session appeared" "$(cat "$work/first" 2>/dev/null)"
  fi
  drop_mirrors
  tmux -L "$socket" kill-window -t tabB:need-win 2>/dev/null
  tmux -L "$socket" set-option -pu -t "$ask_pane" @claude_state

  # A REMOTE blocked agent must be refused, not opened. This is the half of the
  # selection rule that has no local equivalent and the worst failure mode: the
  # view is opened with `display-popup` against a window id from ANOTHER tmux
  # server, which does not fail -- @9 exists on this one too -- so the key would
  # quietly mirror whatever local window happens to carry that id. The rule is
  # one host test in answer_verdict, and nothing else would notice it going.
  tmux -L "$socket" new-window -t tabB -n ssh-pane "$IDLE"
  ssh_pane=$(tmux -L "$socket" list-panes -t tabB:ssh-pane -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$ssh_pane" @ssh_my_machine 1
  tmux -L "$socket" set-option -p -t "$ssh_pane" @ssh_host bakery
  # Its own stub directory, NOT $work/stub: that one is where the fzf stub
  # lives, and the remote section above deliberately deletes its `ssh` when it
  # is done so the local cases cannot pick it up. Same reason $work/wstub exists
  # further down. It reports one asking agent, which -- ask-win having been
  # cleared just above -- is now the only blocked row anywhere.
  mkdir -p "$work/sshstub"
  cat >"$work/sshstub/ssh" <<STUB
#!/bin/sh
for a in "\$@"; do cmd=\$a; done
fmt=\${cmd#*-F \'}
prefix=\${fmt%%#\{*}
printf '%s%s\t@9\t%%9\tremote-win\tasking\t%s\tremote note\n' "\$prefix" remote-sess $((now - 900))
STUB
  chmod +x "$work/sshstub/ssh"
  # The whole sentence, not just "remote": the log is server-wide and keeps
  # growing, so a one-word needle can be satisfied by an unrelated message from
  # an earlier section.
  refused=$(said_count "the blocked agent is remote")
  answer_first "$work/sshstub"
  if wait_said "$refused" "the blocked agent is remote" && [ "$(mirrors)" = 0 ]; then
    pass "prefix + A refuses a remote agent instead of opening a local window id"
  else
    fail "prefix + A refuses a remote agent instead of opening a local window id" \
      "sessions: $(tmux -L "$socket" list-sessions -F '#{session_name}' | tr '\n' ' ')" \
      "messages: $(msg_log | head -3 | tr "\n" "|")" \
      "$(cat "$work/first" 2>/dev/null)"
  fi
  drop_mirrors

  # A remote blocked row that is OLDER than a local one sorts first, and must
  # not end the scan: it is skipped, and the local one is still answered. Every
  # case above had the remote row as the only blocked one, so a scan that
  # stopped at the first blocked row of any kind passed them all.
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_state asking
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_since "$now"
  answer_first "$work/sshstub"
  if wait_mirror; then
    shown=$(tmux -L "$socket" list-clients -F '#{client_session} #{window_name}' |
      awk '$1 ~ /^_agent_/ { print $2; exit }')
    if [ "$shown" = ask-win ]; then
      pass "prefix + A skips an older remote blocked row and answers the local one"
    else
      fail "prefix + A skips an older remote blocked row and answers the local one" \
        "the view is showing [$shown]"
    fi
  else
    fail "prefix + A skips an older remote blocked row and answers the local one" \
      "no mirror session appeared" "$(cat "$work/first" 2>/dev/null)"
  fi
  drop_mirrors
  tmux -L "$socket" kill-window -t tabB:ssh-pane 2>/dev/null

  # The third of the three silences: no agent on the server at all. Every pane's
  # state is set aside for the one run and put back after, since the cases that
  # follow read them.
  agent_panes=$(tmux -L "$socket" list-panes -a -F '#{pane_id} #{@claude_state}' | awk 'NF == 2')
  while read -r p st; do
    [ -n "$p" ] && tmux -L "$socket" set-option -pu -t "$p" @claude_state
  done <<<"$agent_panes"
  refused=$(said_count "no Claude agents running")
  answer_first
  if wait_said "$refused" "no Claude agents running" && [ "$(mirrors)" = 0 ]; then
    pass "prefix + A with no agent anywhere says so, rather than 'nothing is waiting'"
  else
    fail "prefix + A with no agent anywhere says so, rather than 'nothing is waiting'" \
      "messages: $(msg_log | tail -3 | tr "\n" "|")" "$(cat "$work/first" 2>/dev/null)"
  fi
  while read -r p st; do
    [ -n "$p" ] && tmux -L "$socket" set-option -p -t "$p" @claude_state "$st"
  done <<<"$agent_panes"
  tmux -L "$socket" set-option -p -t "$ask_pane" @claude_state asking
fi

# --answer-first refuses to run without a client rather than guessing one: with
# no client there is nowhere to put the popup, and a usage error is the one
# answer that shows up in a `tmux run-shell` log instead of vanishing.
# tmux reports the non-zero exit on its own stderr ("... returned 2"), which is
# the expected result here and would otherwise read as a failure in the log.
if tmux -L "$socket" run-shell "cd $PWD && PATH=$PWD/bin:\$PATH tmux-agents --answer-first >$work/usage 2>&1" >/dev/null 2>&1; then
  fail "--answer-first without a client is a usage error" "it exited 0"
else
  if grep -q 'usage:' "$work/usage" 2>/dev/null; then
    pass "--answer-first without a client is a usage error"
  else
    fail "--answer-first without a client is a usage error" "$(cat "$work/usage" 2>/dev/null)"
  fi
fi

# --- the enter decision, on its own ---------------------------------------------

# enter refuses a row from INSIDE fzf, so that a row it cannot act on leaves the
# picker standing with the reason in its header instead of closing the popup and
# printing to a status line behind it. The binding cannot work that out from the
# row alone -- whether a WezTerm tab shows that window takes tmux, and maybe
# wezterm, to answer -- so it re-enters the script as `--jump-check`, which
# prints the fzf actions to run.
#
# That mode is worth pinning on its own: it is the half that decides, it needs
# no pty, and each of its answers is a different silent failure. Accepting a row
# that cannot be jumped to makes enter close the popup and do nothing; refusing
# one that can makes enter dead.
jump_check() {
  rm -f "$work/jc"
  tmux -L "$socket" run-shell "cd $PWD && PATH=$work/wstub:$PWD/bin:\$PATH tmux-agents --jump-check '$1' >$work/jc 2>&1"
  for _ in $(seq 1 20); do
    [ -s "$work/jc" ] && break
    sleep 0.2
  done
  cat "$work/jc" 2>/dev/null
}

# A detached session of its own, so no client shows its window -- arranged here
# rather than borrowed from whichever session an earlier section left alive.
tmux -L "$socket" new-session -d -s jc "$IDLE"
jc_win=$(tmux -L "$socket" list-windows -t jc -F '#{window_id}' | head -1)
jc_pane=$(tmux -L "$socket" list-panes -t "$jc_win" -F '#{pane_id}' | head -1)

out=$(jump_check "|$jc_win|$jc_pane|asking")
case "$out" in
  "change-header(enter: nothing is showing that window"*)
    pass "--jump-check refuses a window no client is showing"
    ;;
  *) fail "--jump-check refuses a window no client is showing" "got: $out" ;;
esac

out=$(jump_check "no-such-host|@9|%9|asking")
case "$out" in
  "change-header(enter: no local pane is connected to no-such-host)"*)
    pass "--jump-check refuses a remote row with no ssh pane to land on"
    ;;
  *) fail "--jump-check refuses a remote row with no ssh pane to land on" "got: $out" ;;
esac

# Every refusal must be a change-header and nothing else: a stray accept here is
# an enter that closes the popup and does nothing, which is the exact complaint
# this whole path exists to answer.
case "$out" in
  *accept*) fail "a refusal never accepts" "got: $out" ;;
  *) pass "a refusal never accepts" ;;
esac

# --- the ctrl-o decision, on its own --------------------------------------------

# ctrl-o asks `--answer-check`, the same way enter asks --jump-check, so that
# which rows it answers is decided by the one list of blocked states the glyph,
# the ranking and prefix + A also read. It needs no tmux -- the decision is in
# the key field -- so it is run directly. Accepting a row it cannot answer opens
# the view on an agent that is not waiting; refusing one it can makes the key
# dead on a row the tab bar just painted red.
answer_check() {
  "$PWD/bin/tmux-agents" --answer-check "$1" 2>&1
}

for st in asking waiting needs_input; do
  out=$(answer_check "|@1|%1|$st")
  if [ "$out" = "print(ctrl-o)+accept" ]; then
    pass "--answer-check accepts a local $st row"
  else
    fail "--answer-check accepts a local $st row" "got: $out"
  fi
done

out=$(answer_check "bakery|@9|%9|needs_input")
if [ "$out" = "change-header(ctrl-o: a remote agent cannot be answered here yet)" ]; then
  pass "--answer-check refuses a remote blocked row, saying why"
else
  fail "--answer-check refuses a remote blocked row, saying why" "got: $out"
fi

# "Not blocked" is decided before "remote". prefix + A reads the same verdict to
# choose between "the blocked agent is remote" and "nothing is waiting on you",
# so with the two tests swapped it would report a remote block that is not there.
out=$(answer_check "bakery|@9|%9|busy")
if [ "$out" = "change-header(ctrl-o: that session is not waiting on you)" ]; then
  pass "--answer-check calls a remote row that is not blocked not waiting, not remote"
else
  fail "--answer-check calls a remote row that is not blocked not waiting, not remote" "got: $out"
fi

for st in busy idle stalled ""; do
  out=$(answer_check "|@1|%1|$st")
  if [ "$out" = "change-header(ctrl-o: that session is not waiting on you)" ]; then
    pass "--answer-check refuses a local row in state [$st]"
  else
    fail "--answer-check refuses a local row in state [$st]" "got: $out"
  fi
done

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
for _ in $(seq 1 100); do
  tmux -L "$socket" list-clients -F '#{client_session}' 2>/dev/null |
    grep -q '^_agent_' || break
  sleep 0.05
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
  for _ in $(seq 1 200); do
    grep -q -- "$1" <<<"$(screen)" && return 0
    sleep 0.05
  done
  return 1
}

# type_query <text> — type a query that matches exactly one row, and return once
# fzf shows that it has filtered. fzf matches in the background, so a key sent
# right after the query can act on the unfiltered list -- on its first row,
# which is not the one typed. The match count (`1/N` on the info line) is the
# observable for "done", read together with the query on the prompt line so a
# list that held one row before the typing cannot satisfy it early. This
# replaces a fixed 0.4s that only usually was long enough.
type_query() {
  local s
  tmux -L "$socket" send-keys -t "$fzf_pane" "$1"
  for _ in $(seq 1 200); do
    s=$(screen)
    case "$s" in *"> $1"*) grep -q ' 1/[0-9]' <<<"$s" && return 0 ;; esac
    sleep 0.05
  done
  # Named here, so the case after it does not take the blame: a key sent now
  # lands on whatever row the unfiltered list has first.
  fail "harness: the query $1 narrows the picker to one row" "$s"
  return 1
}

if ! wait_screen 'b-ask'; then
  fail "the picker renders in a real pane" "$(screen)" "$(cat "$work/real" 2>/dev/null)"
else
  pass "the picker renders in a real pane"

  # asking sorts above busy, so the second row is the one ctrl-o must refuse.
  # Both keys in one send-keys, with no pause between: fzf handles key events
  # one at a time in arrival order, so C-o acts on the row Down moved to. (Not
  # a query, which would hide the rows the cursor cases below move between.)
  tmux -L "$socket" send-keys -t "$fzf_pane" Down C-o

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

  # The list refreshes itself. Nothing below presses a key: a session that
  # appears after the picker was drawn has to show up on its own, because the
  # states this list reports change while you are looking at it -- 🛑 arrives 6s
  # after the dialog does, so a picker opened to find out who is blocked can be
  # drawn just before the answer it exists to give.
  #
  # This is the only case that fails if the refresh bindings are deleted.
  # `busy` with a fresh timestamp, so the new row lands at the bottom and the
  # cursor assertions below keep their footing.
  tmux -L "$socket" new-window -t bindB -n b-appeared "$IDLE"
  appeared=$(tmux -L "$socket" list-panes -t bindB:b-appeared -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$appeared" @claude_state busy
  tmux -L "$socket" set-option -p -t "$appeared" @claude_since "$(date +%s)"
  if wait_screen 'b-appeared'; then
    pass "the list refreshes itself while the picker is open"
  else
    fail "the list refreshes itself while the picker is open" "$(screen)"
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
  # the pane exit at all. Dead AND silent, as the needs_input case below
  # explains: the pane also dies when the script errors out, so "it exited"
  # alone would report a crash as an accepted key.
  tmux -L "$socket" send-keys -t "$fzf_pane" C-o
  for _ in $(seq 1 200); do
    [ "$(dead)" = 1 ] && break
    sleep 0.05
  done
  if [ "$(dead)" = 1 ] && [ ! -s "$work/real" ]; then
    pass "ctrl-o on a blocked row is accepted"
  else
    fail "ctrl-o on a blocked row is accepted" "pane_dead=$(dead)" \
      "log: $(cat "$work/real" 2>/dev/null)" "$(screen)"
  fi

  # needs_input is accepted too, and it gets its own run rather than riding on
  # the row above: it ranks BELOW asking/waiting, so with an asking row present
  # it is never the row under the cursor, and a gate that still excluded it
  # would go unnoticed. The binding's --answer-check is the only thing that
  # distinguishes the two, and a state missing from it is silent -- the key
  # simply does nothing on a row the tab bar has painted red. It matters because
  # prefix + A answers "the first red one", and red is all three states.
  tmux -L "$socket" kill-window -t bindB:b-ask 2>/dev/null
  tmux -L "$socket" new-window -t bindB -n b-needs "$IDLE"
  p=$(tmux -L "$socket" list-panes -t bindB:b-needs -F '#{pane_id}' | head -1)
  tmux -L "$socket" set-option -p -t "$p" @claude_state needs_input
  tmux -L "$socket" set-option -p -t "$p" @claude_since "$(date +%s)"
  tmux -L "$socket" respawn-pane -k -t "$fzf_pane" \
    "sh -c 'PATH=$PWD/bin:\$PATH tmux-agents >$work/real 2>&1'"
  if ! wait_screen 'b-needs'; then
    fail "the picker lists a needs_input row" "$(screen)" "$(cat "$work/real" 2>/dev/null)"
  else
    tmux -L "$socket" send-keys -t "$fzf_pane" C-o
    for _ in $(seq 1 200); do
      [ "$(dead)" = 1 ] && break
      sleep 0.05
    done
    # Dead AND silent. The pane also dies when the script errors out, and the
    # fixture right above it was just rebuilt -- so "it exited" on its own would
    # report a broken fixture as a working gate. With no client attached here
    # the accepted path ends at the script's own no-client guard, which says
    # nothing; anything in the log means it got there another way.
    if [ "$(dead)" = 1 ] && [ ! -s "$work/real" ]; then
      pass "ctrl-o on a needs_input row is accepted"
    else
      fail "ctrl-o on a needs_input row is accepted" "pane_dead=$(dead)" \
        "log: $(cat "$work/real" 2>/dev/null)" "$(screen)"
    fi
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
    # SHELL=/bin/sh, because fzf runs a transform through $SHELL and the login
    # shell here is zsh, which REBUILDS $PATH for every `zsh -c` -- so the
    # wezterm stub below would be invisible to the enter binding and the whole
    # success path would silently take the "no tab" branch. sh keeps the
    # environment it is given.
    #
    # FZF_DEFAULT_OPTS carries the one setting of the author's .zshenv that
    # breaks this picker quietly: --accept-nth=-1 prints only the last field,
    # dropping the key the jump parses. Neither CI nor the container sets it, so
    # without this the script's reset of the variable was untested everywhere
    # except the one machine it exists for.
    tmux -L "$socket" respawn-pane -k -t "$fzf_pane" \
      "sh -c 'SHELL=/bin/sh FZF_DEFAULT_OPTS=--accept-nth=-1 PATH=$work/wstub:$PWD/bin:\$PATH tmux-agents >$work/real2 2>&1'"
    wait_screen "$1" || return 1
    type_query "$1" || return 1
    tmux -L "$socket" send-keys -t "$fzf_pane" Enter
    return 0
  }

  # Waits for whichever outcome enter is supposed to have, so neither case pays
  # the other's timeout: acceptance closes the picker, a refusal leaves it up
  # with the reason in its header.
  wait_dead() {
    for _ in $(seq 1 200); do
      [ "$(dead)" = 1 ] && return 0
      sleep 0.05
    done
    return 1
  }

  # A directory of its own, NOT $work/stub: that one holds the fzf stub, and
  # putting it on the path here would replace the real fzf this section exists
  # to drive -- the picker would render nothing and every case below would fail
  # for a reason that has nothing to do with the jump.
  mkdir -p "$work/wstub"
  rm -f "$work/wstub/wezterm"
  # No client is attached to bindB yet, so this is the "nothing is showing that
  # window" refusal. Each refusal case waits for its own reason, never for the
  # bare "enter: " -- the hint on screen from the start begins with that too,
  # so waiting for it read the screen before enter had been handled at all.
  if ! press_enter b-jump; then
    fail "the picker lists the jump fixture" "$(screen)"
  else
    # The point of refusing inside fzf: the popup stays, and says why. A
    # refusal that closed it would be a popup that vanishes with the reason on
    # a status line somewhere behind it.
    if wait_screen 'nothing is showing'; then
      pass "enter on a window no client shows warns in the header"
    else
      fail "enter on a window no client shows warns in the header" "$(screen)"
    fi
    if [ "$(dead)" = 0 ]; then
      pass "and leaves the picker open"
    else
      fail "and leaves the picker open" "the pane exited" "$(screen)"
    fi
    active=$(tmux -L "$socket" display-message -p -t bindB:b-jump '#{pane_id}')
    if [ "$active" = "$jump_other" ]; then
      pass "enter on a window no client shows touches nothing"
    else
      fail "enter on a window no client shows touches nothing" \
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
  # Like the real `cli list`, it returns every pane, with the match neither
  # first nor last, so taking `.[0]` without the tty filter would raise tab 5.
  pty_attach bindB
  agent_tty=""
  for _ in $(seq 1 120); do
    agent_tty=$(tmux -L "$socket" list-clients -F '#{client_name} #{client_session}' |
      awk '$2 == "bindB" { print $1; exit }')
    [ -n "$agent_tty" ] && break
    sleep 0.05
  done

  if [ -z "$agent_tty" ]; then
    fail "a pty client can be attached to the agent's session" \
      "script output: [$(tr -d '\r' <"$work/pty.log" 2>/dev/null | head -3 | tr '\n' '|')]"
  else
    # A client now shows the window, but there is still no wezterm to ask: the
    # "no WezTerm tab" refusal, which replaced a switch-client fallback that
    # left two clients on one session. Reachable only with a client attached,
    # which is why it sits here and not with the case above.
    if ! press_enter b-jump; then
      fail "the picker lists the jump fixture (no-tab case)" "$(screen)"
    else
      if wait_screen 'no WezTerm tab'; then
        pass "enter with no WezTerm tab to raise warns in the header"
      else
        fail "enter with no WezTerm tab to raise warns in the header" "$(screen)"
      fi
      if [ "$(dead)" = 0 ]; then
        pass "and leaves the picker open (no-tab case)"
      else
        fail "and leaves the picker open (no-tab case)" "the pane exited" "$(screen)"
      fi
      active=$(tmux -L "$socket" display-message -p -t bindB:b-jump '#{pane_id}')
      if [ "$active" = "$jump_other" ]; then
        pass "enter with no WezTerm tab to raise touches nothing"
      else
        fail "enter with no WezTerm tab to raise touches nothing" "active pane moved to $active"
      fi
      clients=$(tmux -L "$socket" list-clients -F '#{client_name} #{client_session}' |
        awk -v t="$agent_tty" '$1 == t { print $2 }')
      if [ "$clients" = bindB ]; then
        pass "and the client showing the agent stays where it was"
      else
        fail "and the client showing the agent stays where it was" "it is on [$clients]"
      fi
    fi

    cat >"$work/wstub/wezterm" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$work/wezterm-calls"
case "\$*" in
  *list*) printf '[{"tab_id": 5, "tty_name": "/dev/pts/990"}, {"tab_id": 77, "tty_name": "%s"}, {"tab_id": 9, "tty_name": "/dev/pts/991"}]\n' "$agent_tty" ;;
esac
exit 0
STUB
    chmod +x "$work/wstub/wezterm"
    : >"$work/wezterm-calls"

    if ! press_enter b-jump; then
      fail "the picker lists the jump fixture (wezterm case)" "$(screen)"
    else
      wait_dead || true
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
      # activate-tab leaves OS focus where it was, so the jump also writes OSC
      # 1337 SetUserVar=focus_window to that client's tty, for the handler in
      # wezterm.lua. Editing either side alone stops cross-window jumps
      # silently. script(1) copies everything written to that pty into pty.log.
      if grep -q 'SetUserVar=focus_window=' "$work/pty.log" 2>/dev/null; then
        pass "and asks WezTerm to focus that window"
      else
        fail "and asks WezTerm to focus that window" "no focus_window OSC reached the client's tty"
      fi
    fi

    # A refused ctrl-o must not fall back to the jump -- and only HERE, with a
    # client showing the window and a WezTerm tab to raise, is the jump able to
    # happen at all. Every earlier "does not jump" case ran where the jump
    # itself would have been refused, so it held whether or not the fallback
    # existed. The row is made idle, which ctrl-o refuses and enter accepts.
    tmux -L "$socket" set-option -p -t "$jump_target" @claude_state idle
    no_jump_since() { # no_jump_since <label>
      if grep -q 'activate-tab' "$work/wezterm-calls" 2>/dev/null; then
        fail "$1 raises no tab" "wezterm calls: [$(tr '\n' '|' <"$work/wezterm-calls")]"
      else
        pass "$1 raises no tab"
      fi
      active=$(tmux -L "$socket" display-message -p -t bindB:b-jump '#{pane_id}')
      if [ "$active" = "$jump_other" ]; then
        pass "$1 leaves the agent's pane alone"
      else
        fail "$1 leaves the agent's pane alone" "active pane moved to $active"
      fi
    }
    # Inside the picker: the binding refuses and the picker stays up.
    tmux -L "$socket" select-pane -t "$jump_other"
    : >"$work/wezterm-calls"
    tmux -L "$socket" respawn-pane -k -t "$fzf_pane" \
      "sh -c 'SHELL=/bin/sh PATH=$work/wstub:$PWD/bin:\$PATH tmux-agents >$work/real2 2>&1'"
    if wait_screen b-jump; then
      type_query b-jump
      tmux -L "$socket" send-keys -t "$fzf_pane" C-o
      if wait_screen 'not waiting on you'; then
        pass "ctrl-o on a jumpable idle row is refused in the picker"
      else
        fail "ctrl-o on a jumpable idle row is refused in the picker" "$(screen)"
      fi
      no_jump_since "a ctrl-o refused in the picker"
    else
      fail "the picker lists the jump fixture (ctrl-o case)" "$(screen)"
    fi
    # After the picker: a picker that closed on ctrl-o regardless (an fzf whose
    # binding no longer refuses) hands the script the key and the row. Its own
    # check must refuse too, and stop there.
    tmux -L "$socket" select-pane -t "$jump_other"
    : >"$work/wezterm-calls"
    mkdir -p "$work/ostub"
    cat >"$work/ostub/fzf" <<STUB
#!/bin/sh
row=\$(grep b-jump)
printf '%s\n%s\n' ctrl-o "\$row"
exit 0
STUB
    chmod +x "$work/ostub/fzf"
    # "Nothing happened" also holds for a script that died before deciding, or
    # a stub that handed it an empty row. So the refusal itself is waited for:
    # its sentence logged once more than before the run.
    refusals() {
      tmux -L "$socket" show-messages 2>/dev/null | grep -F 'display-message' |
        grep -cF 'that session is not waiting on you' || true
    }
    refused_before=$(refusals)
    tmux -L "$socket" respawn-pane -k -t "$fzf_pane" \
      "sh -c 'SHELL=/bin/sh PATH=$work/ostub:$work/wstub:$PWD/bin:\$PATH tmux-agents >$work/real2 2>&1'"
    if ! wait_dead; then
      fail "the script handed a ctrl-o after the picker finishes" "$(screen)"
    fi
    for _ in $(seq 1 20); do
      [ "$(refusals)" -gt "$refused_before" ] && break
      sleep 0.1
    done
    if [ "$(refusals)" -gt "$refused_before" ]; then
      pass "a ctrl-o on an idle row after the picker is refused, saying why"
    else
      fail "a ctrl-o on an idle row after the picker is refused, saying why" \
        "output: $(cat "$work/real2" 2>/dev/null)"
    fi
    no_jump_since "a ctrl-o refused after the picker"
    tmux -L "$socket" set-option -p -t "$jump_target" @claude_state waiting

    # enter on a REMOTE row. The agent lives in the remote tmux, so the jump
    # lands on the local pane holding the ssh connection to that host: matched
    # on @ssh_host, then window and pane read back in that order. Only the
    # refusal ("no local pane is connected") was covered; a match on the wrong
    # column, or the two ids swapped, would make every remote jump do nothing.
    # The ssh pane here is b-jump's second pane, which the client shows and the
    # WezTerm stub has a tab for. @ssh_my_machine stays unset, so the listing
    # never tries to reach the host.
    tmux -L "$socket" set-option -p -t "$jump_target" @ssh_host farhost
    tmux -L "$socket" select-pane -t "$jump_other"
    : >"$work/wezterm-calls"
    cat >"$work/ostub/fzf" <<STUB
#!/bin/sh
cat >/dev/null
printf '\nfarhost|@9|%%9|asking\tremote-win\n'
exit 0
STUB
    chmod +x "$work/ostub/fzf"
    tmux -L "$socket" respawn-pane -k -t "$fzf_pane" \
      "sh -c 'SHELL=/bin/sh PATH=$work/ostub:$work/wstub:$PWD/bin:\$PATH tmux-agents >$work/real2 2>&1'"
    wait_dead || true
    if grep -q 'activate-tab --tab-id 77' "$work/wezterm-calls" 2>/dev/null; then
      pass "enter on a remote row raises the tab of the pane connected to that host"
    else
      fail "enter on a remote row raises the tab of the pane connected to that host" \
        "wezterm calls: [$(tr '\n' '|' <"$work/wezterm-calls" 2>/dev/null)]" "$(cat "$work/real2" 2>/dev/null)"
    fi
    active=$(tmux -L "$socket" display-message -p -t bindB:b-jump '#{pane_id}')
    if [ "$active" = "$jump_target" ]; then
      pass "and puts that ssh pane in front"
    else
      fail "and puts that ssh pane in front" "active pane is $active, wanted $jump_target"
    fi
    if tmux -L "$socket" show-messages 2>/dev/null | grep -F 'display-message' | grep -qF 'jumped to (remote window: farhost)'; then
      pass "and says the last hop is in the remote's tmux"
    else
      fail "and says the last hop is in the remote's tmux" \
        "$(tmux -L "$socket" show-messages 2>/dev/null | tail -3 | tr '\n' '|')"
    fi
    tmux -L "$socket" set-option -p -u -t "$jump_target" @ssh_host

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
      if wait_screen 'shown over ssh'; then
        pass "enter on a window shown over ssh says so in the header"
      else
        fail "enter on a window shown over ssh says so in the header" "$(screen)"
      fi
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
