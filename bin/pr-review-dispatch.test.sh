#!/bin/bash
# Exercises bin/pr-review-dispatch, the half of the review pipeline that decides
# whether a session may be interrupted. That decision is the whole point of the
# program, so the assertions are about what does NOT happen: a job left queued
# and a pane left untouched are the passing outcomes for most cases here.
#
# It runs against a REAL tmux server on a throwaway socket (-L, -f /dev/null),
# reached through a thin wrapper on PATH. The contract is what tmux does with
# pane options and send-keys, so a stubbed tmux would keep passing if that
# changed. Only `claude` is stubbed -- nothing here may start a real session.
#
# Panes run `cat > <file>` rather than a shell, for two reasons. Keystrokes land
# in that file verbatim, which is a far more precise assertion than reading the
# rendered screen back with capture-pane; and a real shell would source
# zsh/directory.zsh, whose precmd hook clears pane options a few hundred
# milliseconds after the test sets them (the trap tmux-pane-titles.test.sh
# documents).
#
# Written for bash 3.2 (/bin/bash on macOS): no mapfile, no associative arrays.
set -uo pipefail

DISPATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-review-dispatch"
REAL_TMUX=$(command -v tmux) || { echo "tmux is required"; exit 1; }
command -v jq >/dev/null || { echo "jq is required"; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "want=[$2] got=[$3]"; fi; }

TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
SOCK="prdispatch-$$"
cleanup() { "$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null; /bin/rm -rf "$TMP"; }
trap cleanup EXIT

STATE="$TMP/state"; mkdir -p "$STATE/jobs"
SESS="$TMP/sessions"; mkdir -p "$SESS"
STUB="$TMP/stub"; mkdir -p "$STUB"
WT="$TMP/worktree"; mkdir -p "$WT"

# tmux on PATH is the real binary pinned to the throwaway server.
cat > "$STUB/tmux" <<EOF
#!/bin/bash
exec "$REAL_TMUX" -L "$SOCK" "\$@"
EOF

# claude agents --json answers from a fixture; every other invocation (the
# --bg --resume fallback) is recorded rather than run.
cat > "$STUB/claude" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "agents" ]; then cat "$FIXAGENTS"; exit 0; fi
printf '%s\n' "$*" >> "$RESUMELOG"
[ -f "$RESUMEFAIL" ] && exit 1
exit 0
EOF
chmod +x "$STUB"/*

tm() { "$REAL_TMUX" -L "$SOCK" "$@"; }

# --- fixtures ---------------------------------------------------------------

PID=4242
typed="$TMP/typed.txt"
: > "$typed"
tm -f /dev/null new-session -d -s work "cat > $typed"
PANE=$(tm list-panes -t work -F '#{pane_id}' | head -1)
printf '{"pid":%s,"sessionId":"sess-1","tmux":"work:@0.%s"}\n' "$PID" "${PANE#%}" > "$SESS/$PID.json"
# Rewrite properly: the tmux field is "<session>:<window_id>.<pane_id>".
jq -n --argjson pid "$PID" --arg pane "$PANE" \
  '{pid:$pid, sessionId:"sess-1", tmux:("work:@0." + $pane)}' > "$SESS/$PID.json"

agents() { # agents <status|none>
  if [ "$1" = none ]; then printf '[]' > "$TMP/agents.json"; return; fi
  jq -n --argjson pid "$PID" --arg cwd "$WT" --arg st "$1" \
    '[{pid:$pid, cwd:$cwd, kind:"interactive", sessionId:"sess-1", startedAt:1, status:$st}]' \
    > "$TMP/agents.json"
}

make_job() {
  jq -n --arg wt "$WT" '{
    repo:"acme/widget", pr:42, url:"https://github.com/acme/widget/pull/42",
    title:"a title", branch:"feature/x", worktree:$wt, sessionId:"sess-1",
    status:"pending",
    seen:["review:11","issue:31"],
    pending:[
      {id:"issue:31", kind:"issue", author:"bob", state:null, path:null, line:null,
       body:"line one\nline two with `backticks` and \"quotes\"", at:"2026-09-07T10:00:08Z"},
      {id:"review:12", kind:"review", author:"carol", state:"CHANGES_REQUESTED", path:null, line:null,
       body:"", at:"2026-09-07T10:00:05Z"}
    ],
    updatedAt:"2026-09-07T10:00:09Z"}' > "$STATE/jobs/acme__widget__42.json"
  : > "$typed"
}

job() { jq -r "$1" "$STATE/jobs/acme__widget__42.json"; }

run() {
  PATH="$STUB:$PATH" \
  FIXAGENTS="$TMP/agents.json" RESUMELOG="$TMP/resume.log" RESUMEFAIL="$TMP/resume.fail" \
  PR_REVIEW_WATCH_STATE_DIR="$STATE" CLAUDE_SESSIONS_DIR="$SESS" \
  PR_REVIEW_DISPATCH_RESUME="${RESUME:-0}" \
    "$DISPATCH" 2>&1
}

settle() { # keystrokes reach `cat` asynchronously
  local i=0
  while [ $i -lt 50 ]; do [ -s "$typed" ] && return 0; sleep 0.05; i=$((i + 1)); done
  return 1
}

# --- cases ------------------------------------------------------------------

echo "-- an idle session receives the job --"
agents idle; make_job
tm set-option -p -t "$PANE" -u @claude_state 2>/dev/null
out=$(run)
settle
eq 'reports the send'          'yes'  "$(printf '%s' "$out" | grep -q '^send  acme/widget#42' && echo yes || echo no)"
eq 'pending is cleared'        '0'    "$(job '.pending|length')"
eq 'status becomes delivered'  'delivered' "$(job .status)"
eq 'delivery method recorded'  'send-keys' "$(job .deliveredVia)"
eq 'seen survives delivery'    '2'    "$(job '.seen|length')"
eq 'something was typed'       'yes'  "$([ -s "$typed" ] && echo yes || echo no)"
eq 'the prompt is ONE line'    '1'    "$(wc -l < "$typed" | tr -d ' ')"
eq 'the prompt points at the file' 'yes' \
  "$(grep -q 'acme__widget__42.prompt.md' "$typed" && echo yes || echo no)"

PROMPT="$STATE/jobs/acme__widget__42.prompt.md"
eq 'prompt file written'            'yes' "$([ -s "$PROMPT" ] && echo yes || echo no)"
eq 'prompt file carries the body'   'yes' "$(grep -q 'line two with' "$PROMPT" && echo yes || echo no)"
eq 'wordless verdict is explained'  'yes' "$(grep -q 'the verdict is the message' "$PROMPT" && echo yes || echo no)"

echo "-- a session that is not positively idle is never typed into --"
for st in busy waiting unknown-future-state; do
  agents "$st"; make_job
  out=$(run)
  eq "held while $st"            'yes' "$(printf '%s' "$out" | grep -q '^hold  acme/widget#42' && echo yes || echo no)"
  eq "pending kept while $st"    '2'   "$(job '.pending|length')"
  eq "nothing typed while $st"   ''    "$(cat "$typed")"
done

echo "-- @claude_state overrides an idle report (the two gates disagree) --"
# One AskUserQuestion dialog can be open while the registry still says idle.
# Typing then answers the dialog instead of queueing, so the pane wins.
for st in asking waiting busy; do
  agents idle; make_job
  tm set-option -p -t "$PANE" @claude_state "$st"
  out=$(run)
  eq "held when the pane says $st"  'yes' "$(printf '%s' "$out" | grep -q 'stopped accepting input' && echo yes || echo no)"
  eq "pending kept when pane says $st" '2' "$(job '.pending|length')"
  eq "nothing typed when pane says $st" '' "$(cat "$typed")"
done

echo "-- a finished-but-unread turn (stalled) is safe to type into --"
agents idle; make_job
tm set-option -p -t "$PANE" @claude_state stalled
run >/dev/null
settle
eq 'delivered while stalled' '0' "$(job '.pending|length')"
tm set-option -p -t "$PANE" -u @claude_state

echo "-- no live session: the --bg fallback is opt-in --"
agents none; make_job
: > "$TMP/resume.log"
out=$(run)
eq 'held by default'            '2'  "$(job '.pending|length')"
eq 'says how to enable it'      'yes' "$(printf '%s' "$out" | grep -q 'PR_REVIEW_DISPATCH_RESUME=1' && echo yes || echo no)"
eq 'claude was never invoked'   'no'  "$([ -s "$TMP/resume.log" ] && echo yes || echo no)"

agents none; make_job
RESUME=1 run >/dev/null
eq 'resumes the recorded session' 'yes' \
  "$(grep -q -- '--bg --resume sess-1' "$TMP/resume.log" && echo yes || echo no)"
eq 'pending cleared after resume' '0'        "$(job '.pending|length')"
eq 'method recorded as resume'    'resume'   "$(job .deliveredVia)"

echo "-- a failed resume leaves the job queued --"
agents none; make_job
touch "$TMP/resume.fail"
run >/dev/null
eq 'pending kept when claude fails' '2' "$(job '.pending|length')"
/bin/rm -f "$TMP/resume.fail"

echo "-- a session file naming a dead pane is not a target --"
agents idle; make_job
jq -n --argjson pid "$PID" '{pid:$pid, sessionId:"sess-1", tmux:"work:@0.%99999"}' > "$SESS/$PID.json"
out=$(run)
eq 'held on unresolvable pane'   'yes' "$(printf '%s' "$out" | grep -q 'no resolvable tmux pane' && echo yes || echo no)"
eq 'pending kept'                '2'   "$(job '.pending|length')"
eq 'nothing typed'               ''    "$(cat "$typed")"

echo "-- an empty queue is a no-op --"
jq '.pending = []' "$STATE/jobs/acme__widget__42.json" > "$TMP/e" && mv "$TMP/e" "$STATE/jobs/acme__widget__42.json"
agents idle
eq 'no output for an empty queue' '' "$(run)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
