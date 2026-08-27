#!/bin/bash
# Exercises agent-state.sh against a real, throwaway tmux server.
#
# Real tmux rather than a stubbed `tmux` on $PATH: the whole contract of this
# hook is the four pane user options other things read (set-titles-string in
# .tmux.conf, bin/tmux-agents), so a stub would only assert that the script
# calls the commands it obviously calls, and would keep passing if tmux changed
# what `set-option -p` means. The server runs on its own -L socket with
# `-f /dev/null`, so it neither sees nor disturbs the user's tmux.
#
# The cases that matter most are the `notify` ones: the notification_type
# allow-list is a hard-coded string list against an upstream vocabulary, so it
# is the part most likely to rot silently. A type dropping off the list downgrades
# a blocked session to invisible; a type wrongly added makes a glyph stick forever.
#
# The precedence cases matter for the same reason. `asking` and `waiting` are
# reached by two different hooks that both fire for one AskUserQuestion dialog,
# and `agent_needs_input` can land on top of either — so the order in which
# states may overwrite each other is real logic, not an implementation detail,
# and getting it wrong is invisible until a pane shows the wrong glyph at 2am.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-state.sh"

if [[ ! -x "$HOOK" ]]; then
  printf 'FAIL: %s not found or not executable\n' "$HOOK"
  exit 1
fi

# Hard failure, not a skip: tmux is a baseline dependency of this repo
# (brewfiles/Brewfile-shell), and a test that skips itself is a green check
# proving nothing -- the same reason default.rules.test.sh is kept out of CI.
for tool in tmux jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'FAIL: %s is required to run this test\n' "$tool"
    exit 1
  fi
done

SOCK="agent-state-test-$$"
tmux -L "$SOCK" -f /dev/null new-session -d -s t 'sleep 600' || {
  printf 'FAIL: could not start the test tmux server\n'
  exit 1
}
trap 'tmux -L "$SOCK" kill-server 2>/dev/null' EXIT

PANE=$(tmux -L "$SOCK" list-panes -F '#{pane_id}' | head -1)
# $TMUX is what makes the hook's bare `tmux` calls land on the test server:
# a tmux client resolves its socket from the first field of this variable.
TMUX_ENV=$(tmux -L "$SOCK" display-message -p '#{socket_path},#{pid},0')

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# show-options prints a trailing newline and the glyph carries a meaningful
# trailing space, so a bare $(...) would eat exactly the character under test.
# The sentinel dot preserves it across the substitution.
get_opt() {
  local v
  v=$(tmux -L "$SOCK" show-options -p -t "$PANE" -qv "$1"; printf .)
  v=${v%.}
  printf '%s' "${v%$'\n'}"
}

run() {
  local mode=$1 stdin=${2-}
  printf '%s' "$stdin" | TMUX="$TMUX_ENV" TMUX_PANE="$PANE" "$HOOK" "$mode"
}

assert_opt() {
  local name=$1 want=$2 got
  got=$(get_opt "$name")
  if [[ "$got" == "$want" ]]; then
    ok "$name = [$want]"
  else
    bad "$name want=[$want] got=[$got]"
  fi
}

assert_exit_zero() {
  local label=$1 status=$2
  if [[ "$status" -eq 0 ]]; then
    ok "exit 0: $label"
  else
    bad "exit $status (want 0): $label"
  fi
}

notify_json() { jq -cn --arg t "$1" --arg m "${2-}" '{notification_type:$t, message:$m}'; }

echo "-- no tmux context: publishes nothing, never fails --"
out=$(TMUX='' TMUX_PANE='' "$HOOK" busy 2>&1); assert_exit_zero "TMUX unset" $?
if [[ -z "$out" ]]; then ok "no output without tmux"; else bad "unexpected output: $out"; fi
out=$(TMUX="$TMUX_ENV" TMUX_PANE='' "$HOOK" busy 2>&1); assert_exit_zero "TMUX_PANE unset" $?
assert_opt @claude_state ''

echo "-- busy --"
run busy; assert_exit_zero "busy" $?
assert_opt @claude_state busy
# The separator is per-glyph, not uniform: 🔶 🛑 🔘 are emoji-presentation and
# already two cells wide, so only the narrow ▶ carries a trailing space.
# Pinned exactly, because the title format concatenates it blind.
assert_opt @claude_glyph '▶ '
since=$(get_opt @claude_since)
now=$(date +%s)
if [[ "$since" =~ ^[0-9]+$ ]] && (( now - since >= 0 && now - since < 60 )); then
  ok "@claude_since is a fresh epoch"
else
  bad "@claude_since not a fresh epoch: [$since]"
fi

echo "-- notify: types that mean 'a dialog is open' --"
for t in permission_prompt elicitation_dialog elicitation_url_dialog; do
  run clear
  run notify "$(notify_json "$t" "waiting on $t")"
  got=$(get_opt @claude_state)
  if [[ "$got" == waiting ]]; then ok "$t -> waiting"; else bad "$t -> [$got], want waiting"; fi
done
assert_opt @claude_glyph '🛑'

echo "-- notify: a background agent blocked on the human --"
run clear
run notify "$(notify_json agent_needs_input 'reviewer needs your input')"
assert_opt @claude_state stalled
assert_opt @claude_glyph '🔘'
assert_opt @claude_note 'reviewer needs your input'

echo "-- ask: the AskUserQuestion dialog --"
run clear
run ask '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which  glyph\nwins?"},{"question":"ignored"}]}}'
assert_exit_zero "ask" $?
assert_opt @claude_state asking
assert_opt @claude_glyph '🔶'
# The first question only, whitespace collapsed: @claude_note is read back on a
# single line by bin/tmux-agents.
assert_opt @claude_note 'Which glyph wins?'

run clear
run ask 'not json at all'; assert_exit_zero "ask with malformed stdin" $?
# Still publishes: the dialog *is* open regardless of what jq made of the input,
# and a missing glyph is a worse failure than a missing note.
assert_opt @claude_state asking
assert_opt @claude_note ''

echo "-- precedence: nothing may demote an open dialog --"
# One AskUserQuestion dialog fires PreToolUse *and*, after a delay, a
# permission_prompt Notification indistinguishable from a tool's. Verified
# against 2.1.247: both send {"notification_type":"permission_prompt",
# "message":"Claude needs your permission"}. The richer state must survive.
run clear
run ask '{"tool_input":{"questions":[{"question":"keep me"}]}}'
run notify "$(notify_json permission_prompt 'Claude needs your permission')"
assert_opt @claude_state asking
assert_opt @claude_glyph '🔶'
assert_opt @claude_note 'keep me'

for from in asking waiting; do
  run clear
  if [[ "$from" == asking ]]; then
    run ask '{"tool_input":{"questions":[{"question":"q"}]}}'
  else
    run notify "$(notify_json permission_prompt 'perm')"
  fi
  run notify "$(notify_json agent_needs_input 'a worker wants you')"
  got=$(get_opt @claude_state)
  if [[ "$got" == "$from" ]]; then
    ok "agent_needs_input does not demote $from"
  else
    bad "agent_needs_input demoted $from -> [$got]"
  fi
done

# idle_prompt is not in the allow-list at all. It fires 60s after a turn ends,
# by which point Stop has already published `stalled`; republishing would only
# restamp @claude_since and reset the picker's age column to 0s. Pinned here
# because "it does nothing" is indistinguishable from "someone deleted the
# branch" unless a test says the nothing is deliberate.
run 'done'
since_before=$(get_opt @claude_since)
run notify "$(notify_json idle_prompt 'Claude is waiting for your input')"
assert_opt @claude_state stalled
if [[ "$(get_opt @claude_since)" == "$since_before" ]]; then
  ok "idle_prompt leaves @claude_since alone"
else
  bad "idle_prompt restamped @claude_since"
fi
assert_opt @claude_note ''

# And answering the dialog clears it, whichever state it was in.
for from in asking waiting; do
  run clear
  if [[ "$from" == asking ]]; then
    run ask '{"tool_input":{"questions":[{"question":"q"}]}}'
  else
    run notify "$(notify_json permission_prompt 'perm')"
  fi
  run busy
  got=$(get_opt @claude_state)
  if [[ "$got" == busy ]]; then ok "busy clears $from"; else bad "busy left $from as [$got]"; fi
done

echo "-- notify: informational types must not stick --"
# Set busy first: the bug this guards is an informational notification
# overwriting a live state, not merely failing to set one.
for t in auth_success agent_completed idle_prompt elicitation_result elicitation_url_result '' unknown_future_type; do
  run busy
  run notify "$(notify_json "$t" "informational")"; status=$?
  got=$(get_opt @claude_state)
  if [[ "$got" == busy && "$status" -eq 0 ]]; then
    ok "${t:-<empty>} left state untouched"
  else
    bad "${t:-<empty>} -> state=[$got] exit=$status, want busy/0"
  fi
done

echo "-- notify: message handling --"
run clear
run notify "$(notify_json permission_prompt $'Bash command\n  wants   to run\trm -rf')"
assert_opt @claude_note 'Bash command wants to run rm -rf'

run clear
long=$(printf 'x%.0s' {1..300})
run notify "$(notify_json permission_prompt "$long")"
note=$(get_opt @claude_note)
if [[ ${#note} -eq 120 ]]; then ok "note truncated to 120 chars"; else bad "note length ${#note}, want 120"; fi

# The PostToolBatch path: once the prompt is answered the note is stale, and a
# stale note in the picker is worse than none.
run busy
assert_opt @claude_note ''
assert_opt @claude_state busy

echo "-- notify: malformed input degrades quietly --"
run busy
run notify 'not json at all'; assert_exit_zero "malformed stdin" $?
assert_opt @claude_state busy
run busy
run notify ''; assert_exit_zero "empty stdin" $?
assert_opt @claude_state busy

echo "-- done: the Stop transition publishes stalled --"
run 'done'; assert_exit_zero 'done' $?
assert_opt @claude_state stalled
assert_opt @claude_glyph '🔘'

echo "-- clear --"
run notify "$(notify_json permission_prompt 'something')"
run clear; assert_exit_zero "clear" $?
for opt in @claude_state @claude_glyph @claude_since @claude_note; do
  assert_opt "$opt" ''
done

echo "-- unknown mode / no mode --"
run busy
run bogus_mode; assert_exit_zero "unknown mode" $?
assert_opt @claude_state busy
TMUX="$TMUX_ENV" TMUX_PANE="$PANE" "$HOOK" </dev/null; assert_exit_zero "no mode" $?
assert_opt @claude_state busy

echo "-- every glyph is emoji-presentation on its own, never VS16 --"
# A base character promoted with VS16 (U+FE0F) is one cell in some terminals and
# two in others. ⚠️ (U+26A0 U+FE0F) was tried for `asking` and visibly misaligned
# the tab title, so the orange diamond stands in for it. Both consumers bake the
# separator into the glyph and align columns on its width, so a VS16 sequence
# slipping back in shifts everything after it with no error anywhere.
check_no_vs16() {
  local label=$1 g
  g=$(get_opt @claude_glyph)
  if printf '%s' "$g" | LC_ALL=C grep -q $'\xef\xb8\x8f'; then
    bad "$label glyph carries VS16 (U+FE0F)"
  else
    ok "$label glyph needs no VS16"
  fi
}
run busy; check_no_vs16 busy
run clear; run ask '{"tool_input":{"questions":[{"question":"q"}]}}'; check_no_vs16 asking
run clear; run notify "$(notify_json permission_prompt 'p')"; check_no_vs16 waiting
run 'done'; check_no_vs16 stalled

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
