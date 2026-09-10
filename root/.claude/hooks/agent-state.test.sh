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

# The hook keeps its per-actor records under $XDG_STATE_HOME, so the test needs
# its own — otherwise it writes into the state of the sessions the developer has
# open, and `clear` here would delete their records. Exported, because the hook
# reads it from the environment it is launched with.
XDG_STATE_HOME=$(mktemp -d)
export XDG_STATE_HOME

trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$XDG_STATE_HOME"' EXIT

PANE=$(tmux -L "$SOCK" list-panes -F '#{pane_id}' | head -1)
# $TMUX is what makes the hook's bare `tmux` calls land on the test server:
# a tmux client resolves its socket from the first field of this variable.
TMUX_ENV=$(tmux -L "$SOCK" display-message -p '#{socket_path},#{pid},0')

pass=0
fail=0

ok() {
  pass=$((pass + 1))
  printf '  ok   %s\n' "$1"
}
# A failure names its section. Most assertions here are made through assert_opt,
# whose message can only describe a value -- "@claude_state want=[waiting]
# got=[busy]" says nothing about which of the twenty-odd scenarios produced it,
# and this file is one long script rather than a set of named cases.
bad() {
  fail=$((fail + 1))
  printf '  FAIL [%s] %s\n' "$current_section" "$1"
}

# Sections are also the reset point. Every one of them starts from a pane and a
# record set that are empty, so a case cannot silently inherit state from the
# case above it -- which used to mean four stale pane options and now means a
# whole set of subagent records. Cases that want to build on something set it up
# themselves, below the header.
current_section="<none>"
section() {
  current_section=$1
  run clear
  printf -- '-- %s --\n' "$1"
}

# show-options prints a trailing newline and the glyph carries a meaningful
# trailing space, so a bare $(...) would eat exactly the character under test.
# The sentinel dot preserves it across the substitution.
get_opt() {
  local v
  v=$(
    tmux -L "$SOCK" show-options -p -t "$PANE" -qv "$1"
    printf .
  )
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

section "no tmux context: publishes nothing, never fails"
out=$(TMUX='' TMUX_PANE='' "$HOOK" busy 2>&1)
assert_exit_zero "TMUX unset" $?
if [[ -z "$out" ]]; then ok "no output without tmux"; else bad "unexpected output: $out"; fi
out=$(TMUX="$TMUX_ENV" TMUX_PANE='' "$HOOK" busy 2>&1)
assert_exit_zero "TMUX_PANE unset" $?
assert_opt @claude_state ''

section "busy"
run busy
assert_exit_zero "busy" $?
assert_opt @claude_state busy
# The separator is per-glyph, not uniform: 🔶 🛑 🔘 are emoji-presentation and
# already two cells wide, so only the narrow ▶ carries a trailing space.
# Pinned exactly, because the title format concatenates it blind.
assert_opt @claude_glyph '▶ '
since=$(get_opt @claude_since)
now=$(date +%s)
if [[ "$since" =~ ^[0-9]+$ ]] && ((now - since >= 0 && now - since < 60)); then
  ok "@claude_since is a fresh epoch"
else
  bad "@claude_since not a fresh epoch: [$since]"
fi

section "notify: types that mean 'a dialog is open'"
for t in permission_prompt elicitation_dialog elicitation_url_dialog; do
  run clear
  run notify "$(notify_json "$t" "waiting on $t")"
  got=$(get_opt @claude_state)
  if [[ "$got" == waiting ]]; then ok "$t -> waiting"; else bad "$t -> [$got], want waiting"; fi
done
assert_opt @claude_glyph '🛑'

section "notify: a background agent blocked on the human"
run clear
run notify "$(notify_json agent_needs_input 'reviewer needs your input')"
assert_opt @claude_state stalled
assert_opt @claude_glyph '🔘'
assert_opt @claude_note 'reviewer needs your input'

section "ask: the AskUserQuestion dialog"
run clear
run ask '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which  glyph\nwins?"},{"question":"ignored"}]}}'
assert_exit_zero "ask" $?
assert_opt @claude_state asking
assert_opt @claude_glyph '🔶'
# The first question only, whitespace collapsed: @claude_note is read back on a
# single line by bin/tmux-agents.
assert_opt @claude_note 'Which glyph wins?'

run clear
run ask 'not json at all'
assert_exit_zero "ask with malformed stdin" $?
# Still publishes: the dialog *is* open regardless of what jq made of the input,
# and a missing glyph is a worse failure than a missing note.
assert_opt @claude_state asking
assert_opt @claude_note ''

section "precedence: nothing may demote an open dialog"
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

section "notify: informational types must not stick"
# Set busy first: the bug this guards is an informational notification
# overwriting a live state, not merely failing to set one.
for t in auth_success agent_completed idle_prompt elicitation_result elicitation_url_result '' unknown_future_type; do
  run busy
  run notify "$(notify_json "$t" "informational")"
  status=$?
  got=$(get_opt @claude_state)
  if [[ "$got" == busy && "$status" -eq 0 ]]; then
    ok "${t:-<empty>} left state untouched"
  else
    bad "${t:-<empty>} -> state=[$got] exit=$status, want busy/0"
  fi
done

section "notify: message handling"
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

section "notify: malformed input degrades quietly"
run busy
run notify 'not json at all'
assert_exit_zero "malformed stdin" $?
assert_opt @claude_state busy
run busy
run notify ''
assert_exit_zero "empty stdin" $?
assert_opt @claude_state busy

section "done: the Stop transition publishes stalled"
run 'done'
assert_exit_zero 'done' $?
assert_opt @claude_state stalled
assert_opt @claude_glyph '🔘'

section "clear"
run notify "$(notify_json permission_prompt 'something')"
run clear
assert_exit_zero "clear" $?
for opt in @claude_state @claude_glyph @claude_since @claude_note; do
  assert_opt "$opt" ''
done

section "unknown mode / no mode"
run busy
run bogus_mode
assert_exit_zero "unknown mode" $?
assert_opt @claude_state busy
TMUX="$TMUX_ENV" TMUX_PANE="$PANE" "$HOOK" </dev/null
assert_exit_zero "no mode" $?
assert_opt @claude_state busy

section "every glyph is emoji-presentation on its own, never VS16"
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
run busy
check_no_vs16 busy
run clear
run ask '{"tool_input":{"questions":[{"question":"q"}]}}'
check_no_vs16 asking
run clear
run notify "$(notify_json permission_prompt 'p')"
check_no_vs16 waiting
run 'done'
check_no_vs16 stalled

section "several actors in one pane"
# Hooks fire inside subagents too, carrying agent_id/agent_type, so one pane can
# hold the main thread plus one state per running subagent. These cases are the
# reason the hook keeps per-actor records at all: the published options are a
# derived view over them, and every failure below was a real symptom — a tab
# claiming progress while a dialog sat unanswered.
RS=$'\036'
US=$'\037'

# $1 agent_id, $2 agent_type, $3.. extra top-level JSON fields (already ",key:v")
agent_json() {
  jq -cn --arg id "$1" --arg t "$2" --arg n "${3-}" --arg m "${4-}" \
    '{agent_id:$id, agent_type:$t}
     + (if $n == "" then {} else {notification_type:$n} end)
     + (if $m == "" then {} else {message:$m} end)'
}

# The reported bug, as a regression test. Two subagents run; one of them is
# blocked on a permission prompt; the other keeps working. Before per-actor
# records, the second one's PostToolBatch overwrote the first one's `waiting`
# with `busy` and the tab showed ▶ while nothing could proceed.
run clear
run subagent-start "$(agent_json A Explore)"
run subagent-start "$(agent_json B Plan)"
run busy
run notify "$(agent_json A Explore permission_prompt 'Bash wants to run rm -rf')"
run busy "$(agent_json B Plan)"
run busy "$(agent_json B Plan)"
assert_opt @claude_state waiting
assert_opt @claude_glyph '🛑'
# Which actor is blocked is the first thing you need, so the label leads the note.
assert_opt @claude_note 'Explore: Bash wants to run rm -rf'

# ...and the blocked subagent's own next batch is what clears it, not anyone
# else's. Answering the prompt lets that agent proceed; nothing else may speak
# for it.
run busy "$(agent_json A Explore)"
assert_opt @claude_state busy
assert_opt @claude_glyph '▶ '

section "precedence across actors: blocked outranks running"
for blocked in asking waiting; do
  run clear
  run subagent-start "$(agent_json A Explore)"
  run busy                           # main: working
  run busy "$(agent_json A Explore)" # subagent: working
  if [[ "$blocked" == asking ]]; then
    run ask '{"tool_input":{"questions":[{"question":"which one?"}]}}'
  else
    run notify "$(notify_json permission_prompt 'perm')"
  fi
  got=$(get_opt @claude_state)
  if [[ "$got" == "$blocked" ]]; then
    ok "a running subagent does not mask main's $blocked"
  else
    bad "main's $blocked was masked -> [$got]"
  fi
done

# asking outranks waiting: it is the only state whose note cannot be
# reconstructed from anywhere else, so it is the one worth showing.
run clear
run notify "$(notify_json permission_prompt 'perm on main')"
run ask "$(jq -cn '{agent_id:"A", agent_type:"Explore",
                    tool_input:{questions:[{question:"pick one"}]}}')"
assert_opt @claude_state asking
assert_opt @claude_note 'Explore: pick one'

section "ties go to the actor blocked longest"
run clear
run subagent-start "$(agent_json A Explore)"
run notify "$(agent_json A Explore permission_prompt 'older')"
older=$(get_opt @claude_since)
# A whole second of sleep, grudgingly: the records carry epoch seconds, so two
# actors blocked inside the same second are a genuine tie and would exercise the
# note tie-break instead of the age one this case is about.
sleep 1
run notify "$(notify_json permission_prompt 'newer')"
assert_opt @claude_since "$older"
assert_opt @claude_note 'Explore: older'

section "SubagentStop is what removes an actor"
run clear
run busy # main busy
run subagent-start "$(agent_json A Explore)"
run notify "$(agent_json A Explore permission_prompt 'blocked')"
assert_opt @claude_state waiting
run subagent-stop "$(agent_json A Explore)"
assert_opt @claude_state busy
assert_opt @claude_note ''

# Stop (the `done` transition) must NOT drop the subagent records: a backgrounded
# agent outlives the turn that launched it, and dropping it here would hide
# exactly the agent most likely to be waiting on you.
run clear
run subagent-start "$(agent_json A Explore)"
run notify "$(agent_json A Explore agent_needs_input 'Explore needs your input')"
run 'done'
# The agent is still blocked on the human, and that outranks the finished turn.
assert_opt @claude_state stalled
assert_opt @claude_note 'Explore: Explore needs your input'
run subagent-start "$(agent_json B Plan)"
run 'done'
# A background agent that is still working means the pane is still working,
# whatever the main turn did — but the point of the case is that neither
# record was dropped by Stop.
assert_opt @claude_state busy
count=0
while IFS= read -r entry; do
  [[ -n "$entry" ]] && count=$((count + 1))
done <<<"$(get_opt @claude_agents | tr "$RS" '\n')"
if [[ "$count" -eq 3 ]]; then
  ok "Stop keeps every background subagent's record"
else
  bad "Stop left $count actors, want 3 (main + two subagents)"
fi

section "concurrent actors: the hook races with itself"
# Subagents launched in one message fire SubagentStart simultaneously, so several
# copies of the hook derive and publish at once. Everything else in this file is
# sequential and cannot see that. Before publish() re-derived after writing, a
# copy whose scan missed a record published a view short of an actor, and the
# `.published` file — written before the options back then — could leave the
# pane holding the short view while claiming the complete one, so every later
# event skipped as a no-op.
#
# Both metrics are asserted. The listing going short of the records is what this
# fixture actually reproduces; the glyph is the consequence that makes it matter,
# since the record a copy misses can be the blocked one, and then the tab says
# `busy` while a dialog waits — the whole bug this hook was rewritten to fix.
#
# THIS CASE IS PROBABILISTIC and is therefore not the regression guard. Measured
# against the previous implementation with the corrected fixture: 5 short
# listings in 20 rounds at 16 concurrent starts, 2 in 20 at 12 — it varies with
# machine load, and a handful of rounds can pass on a broken hook. A test that
# passes on broken code proves nothing, so this is a smoke test that a burst does
# not corrupt anything outright; the deterministic case below it is what pins the
# rule the fix rests on.
concurrent_agents=16
concurrent_rounds=4
race_short=0
race_wrong=0
for _round in $(seq 1 "$concurrent_rounds"); do
  run clear
  # The blocked actor is registered FIRST and separately, and nothing else in
  # the burst touches its record. Racing two events for the *same* actor —
  # `subagent-start` and a permission prompt for ag1 — is not the race under
  # test: the two writes land in whichever order the scheduler picks, so the
  # record legitimately ends as `busy` about one round in ten, and the case
  # reports a hook bug that is really a fixture bug. A subagent cannot be
  # blocked before it has started.
  run subagent-start "$(agent_json blocked Explore)"
  for i in $(seq 1 "$concurrent_agents"); do
    run subagent-start "$(agent_json "ag$i" Explore)" &
  done
  # ...while that one is blocked on a permission prompt at the same moment.
  run notify "$(agent_json blocked Explore permission_prompt 'blocked')" &
  wait

  on_disk=0
  for f in "$XDG_STATE_HOME"/claude-agent-state/*/a_*; do
    [[ -e "$f" ]] && on_disk=$((on_disk + 1))
  done
  listed=0
  while IFS= read -r entry; do
    [[ -n "$entry" ]] && listed=$((listed + 1))
  done <<<"$(get_opt @claude_agents | tr "$RS" '\n')"
  [[ "$listed" -ne "$on_disk" ]] && race_short=$((race_short + 1))
  [[ "$(get_opt @claude_state)" != waiting ]] && race_wrong=$((race_wrong + 1))
done

if [[ "$race_wrong" -eq 0 ]]; then
  ok "a blocked actor is never lost to a concurrent burst"
else
  bad "a concurrent burst hid a blocked actor in $race_wrong of $concurrent_rounds rounds"
fi
if [[ "$race_short" -eq 0 ]]; then
  ok "the published listing matches the records after a concurrent burst"
else
  bad "the listing was short of the records in $race_short of $concurrent_rounds rounds"
fi

# The deterministic half, and the reason the race stuck rather than healing: the
# hook keeps a note of what it last published so an unchanged state costs no
# tmux call, and that note is only trustworthy while this process is the only
# writer. Under a burst it is not — another copy can write the note and then
# lose the race to set the options — so with subagents registered the note must
# not be believed.
#
# The divergence is produced here by clearing the options behind the hook's
# back, which is the same end state that interleaving reaches: the note claims
# the complete view, the pane does not have it. Nothing about the note's format
# is assumed, only that a live blocked actor must reappear.
run clear
run subagent-start "$(agent_json A Explore)"
run notify "$(agent_json A Explore permission_prompt 'still blocked')"
assert_opt @claude_state waiting
for opt in @claude_state @claude_glyph @claude_since @claude_note @claude_agents; do
  tmux -L "$SOCK" set-option -p -t "$PANE" -u "$opt"
done
# The follow-up event must derive the *same* view, or it would republish for the
# ordinary reason and prove nothing: re-firing the same notification keeps the
# record byte-identical, because a re-record of an unchanged state preserves its
# timestamp.
run notify "$(agent_json A Explore permission_prompt 'still blocked')"
got=$(get_opt @claude_state)
if [[ "$got" == waiting ]]; then
  ok "a diverged pane is republished while subagents are registered"
else
  bad "a diverged pane kept its stale options: [$got]"
fi

# The single-actor case deliberately keeps the shortcut: with one writer the
# note cannot go stale on its own, and this is the path that runs once per tool
# batch. The cost is that a pane cleared from outside stays cleared until
# something changes — SessionStart is the recovery, and pinning it here is what
# stops that trade-off from being mistaken for an oversight.
run clear
run busy
for opt in @claude_state @claude_glyph @claude_since @claude_note; do
  tmux -L "$SOCK" set-option -p -t "$PANE" -u "$opt"
done
run busy
got=$(get_opt @claude_state)
if [[ -z "$got" ]]; then
  ok "with one actor the no-change shortcut is kept, divergence and all"
else
  bad "the single-actor shortcut republished unexpectedly: [$got]"
fi

section "an actor's timestamp is when it entered the state"
# The age column in the picker means "how long has it been like this", which is
# the only reading that is useful for a pane blocked for an hour. Re-recording an
# unchanged state must therefore keep its timestamp -- and this is the busy path,
# which fires on every tool batch, so a restamp here would peg every age at 0s.
# Pinned for `stalled` further up (through idle_prompt) but not for the state
# that actually repeats.
run busy
since_busy=$(get_opt @claude_since)
sleep 1
run busy
if [[ "$(get_opt @claude_since)" == "$since_busy" ]]; then
  ok "a repeated busy does not restamp @claude_since"
else
  bad "a repeated busy restamped @claude_since"
fi
# ...but a real transition does, or the age would describe the wrong state.
run 'done'
if [[ "$(get_opt @claude_since)" != "$since_busy" ]]; then
  ok "a change of state does restamp it"
else
  bad "busy -> stalled kept the old @claude_since"
fi

section "the pane empties when the last actor goes"
# Reached only through subagent-stop: `clear` wipes the directory outright, so
# the empty-derivation path -- records exist, none of them survives -- has no
# other caller. Its failure is a pane keeping a glyph for an agent that ended.
run subagent-start "$(agent_json A Explore)"
assert_opt @claude_state busy
run subagent-stop "$(agent_json A Explore)"
for opt in @claude_state @claude_glyph @claude_since @claude_note @claude_agents; do
  assert_opt "$opt" ''
done

section "a long note is truncated with its label, not around it"
# The label leads the note, so the two share the 120-character budget: truncating
# the note first and prefixing afterwards would push the option past what a title
# can hold, on exactly the rows that already have the least room.
run subagent-start "$(agent_json A Explore)"
long=$(printf 'y%.0s' {1..300})
run notify "$(agent_json A Explore permission_prompt "$long")"
note=$(get_opt @claude_note)
if [[ ${#note} -eq 120 ]]; then
  ok "the labelled note is 120 characters, label included"
else
  bad "the labelled note is ${#note} characters, want 120"
fi
case "$note" in
  'Explore: '*) ok "the label survives the truncation" ;;
  *) bad "the label was truncated away: [${note:0:20}...]" ;;
esac

section "@claude_agents: one entry per actor, readable from a format"
run clear
run busy
run subagent-start "$(agent_json A Explore)"
run notify "$(agent_json A Explore permission_prompt 'why me')"
listing=$(get_opt @claude_agents)
count=0
while IFS= read -r entry; do
  [[ -n "$entry" ]] && count=$((count + 1))
done <<<"${listing//$RS/$'\n'}"
if [[ "$count" -eq 2 ]]; then ok "@claude_agents lists both actors"; else bad "@claude_agents has $count entries, want 2"; fi
if [[ "$listing" == *"waiting${US}"*"${US}Explore${US}why me"* ]]; then
  ok "@claude_agents carries state, label and note per actor"
else
  bad "@claude_agents entry shape: [$listing]"
fi

# The picker reads this through a `list-panes -F` format — including over ssh,
# where the *remote* tmux expands it — so the control characters have to survive
# that round trip, not merely show-options. If they ever do not, the separator
# is the thing to change, not the consumer.
via_format=$(tmux -L "$SOCK" list-panes -a -F '#{@claude_agents}' | head -1)
if [[ "$via_format" == "$listing" ]]; then
  ok "@claude_agents survives a list-panes format unchanged"
else
  bad "@claude_agents differs through a format"
fi

run clear
assert_opt @claude_agents ''

section "the hot path stays cheap"
# These are behavioural assertions about *cost*, and cost is the one property
# here that no functional test can notice: break any of them and every other
# case in this file still passes, the hook just taxes the inner agent loop.
# PostToolBatch fires once per tool batch, so a fork added here is paid on every
# batch of every session.
#
# Real commands behind the counters, not stubs that fake an answer: the point is
# how many times they are reached, and a fake jq would change what the hook then
# does with the output.
countdir="$XDG_STATE_HOME/counters"
mkdir -p "$countdir/bin"
for tool in jq tmux; do
  {
    printf '#!/bin/sh\n'
    printf 'echo x >>"%s/%s-calls"\n' "$countdir" "$tool"
    printf 'exec %s "$@"\n' "$(command -v "$tool")"
  } >"$countdir/bin/$tool"
  chmod +x "$countdir/bin/$tool"
done
counted_run() {
  local mode=$1 stdin=${2-}
  printf '%s' "$stdin" |
    PATH="$countdir/bin:$PATH" TMUX="$TMUX_ENV" TMUX_PANE="$PANE" "$HOOK" "$mode"
}
count_calls() {
  local n=0
  [[ -f "$countdir/$1-calls" ]] && n=$(grep -c . "$countdir/$1-calls")
  printf '%s' "$n"
}

run clear
: >"$countdir/jq-calls"
counted_run busy '{"hook_event_name":"PostToolBatch"}'
counted_run busy '{"hook_event_name":"PostToolBatch"}'
if [[ "$(count_calls jq)" -eq 0 ]]; then
  ok "busy parses no JSON while the pane has one actor"
else
  bad "busy spawned jq $(count_calls jq) time(s) with no subagent registered"
fi

# The no-change republish: the records say exactly what was last published, so
# there is nothing for a consumer to see and no reason to pay a tmux round trip.
: >"$countdir/tmux-calls"
counted_run busy '{"hook_event_name":"PostToolBatch"}'
if [[ "$(count_calls tmux)" -eq 0 ]]; then
  ok "an unchanged state costs no tmux call"
else
  bad "an unchanged state cost $(count_calls tmux) tmux call(s)"
fi

# Once a subagent is registered the payload has something to say, so exactly one
# jq pass is expected -- and attribution must not be attempted with a shell
# regex over a payload that carries tool output.
run subagent-start "$(agent_json A Explore)"
: >"$countdir/jq-calls"
counted_run busy "$(agent_json A Explore)"
if [[ "$(count_calls jq)" -eq 1 ]]; then
  ok "busy attributes with a single jq pass once a subagent exists"
else
  bad "busy spawned jq $(count_calls jq) time(s) with a subagent registered"
fi

section "free text cannot forge a record separator"
# The notes come from a permission prompt, a question, or an MCP server's
# elicitation dialog, and the last of those is third-party text. RS and US were
# chosen as separators because no *printable* delimiter is safe inside a note —
# but that reasoning only holds if the control characters are stripped, which
# they were not: a message carrying RS split its own record in two and the
# picker rendered a phantom row whose state was the tail of the note.
run clear
run subagent-start "$(agent_json A Explore)"
run notify "$(agent_json A Explore permission_prompt "before${US}after${RS}more")"
note=$(get_opt @claude_note)
if printf '%s' "$note" | LC_ALL=C grep -q '[[:cntrl:]]'; then
  bad "a control character survived into @claude_note: [$note]"
else
  ok "control characters are stripped from a note"
fi
# The text must survive as text, only flattened -- dropping the note entirely
# would pass the check above while losing the one thing it exists to carry.
case "$note" in
  *before*after*more*) ok "the note keeps its words after flattening" ;;
  *) bad "the note lost its content: [$note]" ;;
esac
count=0
while IFS= read -r entry; do
  [[ -n "$entry" ]] && count=$((count + 1))
done <<<"$(get_opt @claude_agents | tr "$RS" '\n')"
if [[ "$count" -eq 1 ]]; then
  ok "one actor still produces exactly one record"
else
  bad "a note forged $count records out of one actor"
fi

section "attribution comes from the top-level key, never from tool output"
# PostToolBatch carries the content of every tool result in the batch, so a file
# the agent just read can contain the *text* "agent_id". Attributing on a shell
# regex over the raw payload would file the main thread's state under a subagent
# that does not exist, and it would do it silently.
run clear
run subagent-start "$(agent_json A Explore)"
run busy "$(jq -cn '{tool_calls:[{tool_name:"Read",
                     content:"agent_id: \"A\", agent_type: \"Explore\""}]}')"
run notify "$(notify_json permission_prompt 'main is blocked')"
assert_opt @claude_state waiting
assert_opt @claude_note 'main is blocked'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
