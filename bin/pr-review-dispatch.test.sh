#!/bin/bash
# Exercises bin/pr-review-dispatch, the half of the review pipeline that decides
# where queued feedback goes and puts it there.
#
# It runs against a REAL Unix domain socket, created with `nc -lU` and read back
# byte for byte. That is the whole reason this file exists in its current shape.
# The message line's schema is NOT documented -- only the auth line is -- and the
# session registry stamps `"peerProtocol":1`, so it is a versioned interface
# that can change under us. A rejected line is indistinguishable from a
# delivered one at the sending end: the socket sends no reply, and a malformed
# line is accepted and dropped in silence. Asserting the exact bytes on a real
# socket is therefore the only thing here that would go red if the protocol
# moved, and it is the assertion to keep working if any other has to give.
#
# The old version of this program typed into a tmux pane, and most of its suite
# was about refusing to type at the wrong moment. None of that survives: a
# socket message is read between tool calls and can never be consumed as a
# permission dialog's answer, so `busy` is not a gate and there is no pane. The
# case named "busy is not a gate" pins that inversion deliberately, because it
# is the one behaviour a reader of the old program would expect to find and not
# find.
#
# `claude` is stubbed -- nothing here may start a real session. Nothing else is:
# git is real, the worktrees are real, and the socket is real.
#
# Written for bash 3.2 (/bin/bash on macOS): no mapfile, no associative arrays.
set -uo pipefail

DISPATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-review-dispatch"
command -v jq >/dev/null || { echo "jq is required"; exit 1; }
command -v nc >/dev/null || { echo "nc is required"; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "want=[$2] got=[$3]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) no "$1" "[$2] does not contain [$3]" ;; esac; }

TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
KILL_PIDS=""
leaked=0
cleanup() {
  # First pass: the pids we know about. The `sleep` holders standing in for live
  # sessions, and the `nc -lU` listeners, which outlive the run whenever a case
  # asserts that nothing was sent -- a listener nobody connects to waits forever,
  # and `-w` does not bound one (verified: still alive after 3.5s with -w 2).
  for p in $KILL_PIDS; do kill "$p" 2>/dev/null; done
  # Reap them so job control cannot print "Terminated" over the results.
  wait 2>/dev/null

  # Second pass, and the one that makes this hold up over time. The bookkeeping
  # above is a rule every future spawn site has to remember, and the original
  # leak here was precisely a site that could not follow it: `( nc ... & )`
  # detached the job, so `$!` never reached the caller and no list could have
  # contained it. Worse, such a process is reparented away, so neither `jobs -p`
  # nor `pgrep -P $$` can see it either.
  #
  # What every spawn site here DOES have in common is that it names this run's
  # temp directory -- sockets, capture files and fixtures all live under it -- so
  # matching on that finds a straggler whatever mechanism started it. A leak is
  # reported as a FAILURE rather than quietly swept, because a leak that only
  # gets cleaned up is one nobody ever fixes.
  local straggler
  straggler=$(pgrep -f "$TMP" 2>/dev/null | grep -v "^$$\$")
  if [ -n "$straggler" ]; then
    leaked=1
    printf '  FAIL leaked %s process(es) that cleanup could not reach:\n' "$(printf '%s\n' "$straggler" | wc -l | tr -d ' ')"
    for p in $straggler; do
      printf '       %s\n' "$(ps -o pid=,command= -p "$p" 2>/dev/null | cut -c1-100)"
      kill "$p" 2>/dev/null
    done
  fi

  /bin/rm -rf "$TMP"
  [ "$leaked" -eq 0 ] || exit 1
}
trap cleanup EXIT

STATE="$TMP/state"; mkdir -p "$STATE/jobs"
SESS="$TMP/sessions"; mkdir -p "$SESS"
STUB="$TMP/stub"; mkdir -p "$STUB"

# A REAL repository with the target as a REAL worktree nested under it, the way
# `gw` lays them out. It has to be real git: the session lookup asks
# `git worktree list` which paths are worktrees, precisely so the outer checkout
# cannot claim a session running in an inner one.
REPO="$TMP/repo"; WT="$REPO/git-worktrees/wt"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feature/x "$WT" >/dev/null 2>&1

cat > "$STUB/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$RESUMELOG"
[ -f "$RESUMEFAIL" ] && exit 1
exit 0
EOF
chmod +x "$STUB"/*

# --- fixtures ---------------------------------------------------------------

# A process we are allowed to kill, standing in for a live session.
#
# The redirections are load-bearing, not tidiness. This is called as
# `PID=$(spawn_holder)`, and a background job started inside a command
# substitution INHERITS the substitution's stdout pipe -- so `sleep 300 &` keeps
# that pipe open and the assignment blocks for the full five minutes, with no
# output and no error to say why. Detaching all three streams is what makes the
# substitution return as soon as the function does.
spawn_holder() {
  sleep 300 >/dev/null 2>&1 &
  KILL_PIDS="$KILL_PIDS $!"
  printf '%s' "$!"
}

# listen <path> <outfile> -- a real inbox socket. `nc -lU` serves exactly one
# connection and exits, which matches one delivery per run.
#
# Its pid is recorded, and that is not housekeeping. Several cases here assert
# that NOTHING was sent, and a listener that is never connected to **waits
# forever**: measured before this, every run leaked three of them (the
# dead-session, worktree-ownership and dry-run cases), still alive hours later
# holding sockets in deleted temp directories. The subshell it used to start in
# (`( nc ... & )`) was what made that invisible -- it detached the job so `$!`
# never reached the caller and nothing could clean up.
listen() {
  /bin/rm -f "$1"
  nc -lU "$1" > "$2" 2>/dev/null &
  KILL_PIDS="$KILL_PIDS $!"
  local i=0
  while [ $i -lt 60 ]; do [ -S "$1" ] && return 0; sleep 0.05; i=$((i + 1)); done
  return 1
}

# Wait for the listener to have written the line out.
settle() {
  local i=0
  while [ $i -lt 60 ]; do [ -s "$1" ] && return 0; sleep 0.05; i=$((i + 1)); done
  return 1
}

# session <file-stem> <pid> <cwd> <socket> <startedAt> [status]
session() {
  jq -n --argjson pid "$2" --arg cwd "$3" --arg sock "$4" \
        --argjson at "$5" --arg st "${6:-idle}" \
    '{pid:$pid, sessionId:("sess-" + ($pid|tostring)), name:("s" + ($pid|tostring)),
      cwd:$cwd, kind:"interactive", startedAt:$at, status:$st,
      messagingSocketPath:$sock}' > "$SESS/$1.json"
}

make_job() { # make_job [worktree]
  jq -n --arg wt "${1:-$WT}" '{
    repo:"acme/widget", pr:42, url:"https://github.com/acme/widget/pull/42",
    title:"a title", branch:"feature/x", worktree:$wt, sessionId:"sess-1",
    status:"pending",
    seen:["review:11","issue:31"],
    pending:[
      {id:"issue:31", kind:"issue", author:"bob", state:null, path:null, line:null,
       body:"line one\nline two with `backticks` and \"quotes\"", at:"2026-09-07T10:00:08Z"},
      {id:"review:12", kind:"review", author:"carol", state:"CHANGES_REQUESTED", path:"a/b.ts", line:9,
       body:"", at:"2026-09-07T10:00:05Z"}
    ],
    updatedAt:"2026-09-07T10:00:09Z"}' > "$STATE/jobs/acme__widget__42.json"
}

job() { jq -r "$1" "$STATE/jobs/acme__widget__42.json"; }
reset() { /bin/rm -f "$STATE"/jobs/* "$SESS"/*.json "$TMP"/wire-* "$TMP/resume.log" "$TMP/resume.fail"; }

run() {
  PATH="$STUB:$PATH" \
  RESUMELOG="$TMP/resume.log" RESUMEFAIL="$TMP/resume.fail" \
  PR_REVIEW_WATCH_STATE_DIR="$STATE" CLAUDE_SESSIONS_DIR="$SESS" \
  PR_REVIEW_DISPATCH_RESUME="${RESUME:-0}" \
    "$DISPATCH" "$@" 2>&1
}

# arrange_and_deliver <tag> -- one live session in $WT with a listener, one job,
# delivered. Sets WIRE to the capture file and `out` to the run's output.
#
# Every group that asserts on a delivery calls this for itself. Three groups used
# to share one Act, asserting on whatever the first had left behind, which made
# them break silently the moment anything was inserted or reordered between them
# -- and left two of them with no Arrange and no Act at all.
arrange_and_deliver() {
  local tag=$1
  reset
  PID=$(spawn_holder); WIRE="$TMP/wire-$tag"; SOCKP="$TMP/s$tag.sock"
  listen "$SOCKP" "$WIRE" || no "listener came up ($tag)"
  session live "$PID" "$WT" "$SOCKP" 100
  make_job
  out=$(run)
  # Checked, not discarded: on a timeout every following assertion reads an empty
  # file and fails as though the protocol were wrong, pointing at the wrong thing.
  settle "$WIRE" || no "nothing reached the socket ($tag)"
}

# --- the wire format --------------------------------------------------------
# The assertion this suite exists for.

printf 'wire format\n'
arrange_and_deliver 1

line=$(cat "$WIRE")
# Newline-terminated and exactly one line: the socket reads line by line, so a
# payload split across two would be read as two messages and a payload with no
# terminator would sit in the buffer until the 30s connection timeout dropped it.
eq "the payload is exactly one line" "1" "$(wc -l < "$WIRE" | tr -d ' ')"
eq "it parses as JSON" "ok" "$(printf '%s' "$line" | jq -e . >/dev/null 2>&1 && echo ok)"
eq "type is user" "user" "$(printf '%s' "$line" | jq -r .type)"
eq "message.role is user" "user" "$(printf '%s' "$line" | jq -r .message.role)"
eq "message.content is a string" "string" "$(printf '%s' "$line" | jq -r '.message.content | type')"
eq "no other top-level keys" "message type" "$(printf '%s' "$line" | jq -r 'keys | join(" ")')"
has "content points at the prompt file" "$(printf '%s' "$line" | jq -r .message.content)" \
  "$STATE/jobs/acme__widget__42.prompt.md"
has "content names the PR" "$(printf '%s' "$line" | jq -r .message.content)" \
  "https://github.com/acme/widget/pull/42"
has "content disclaims the peer framing" "$(printf '%s' "$line" | jq -r .message.content)" \
  "not sent by another agent"
# The receiving terminal previews only the FIRST line until the human expands
# it, and the socket gives a relayed message no usable sender -- `origin` on the
# payload is ignored and `from` arrives as "unknown". So the first line has to
# identify its own source, or the preview reads as an anonymous peer message.
eq "the first line names its source" "ok" \
  "$(printf '%s' "$line" | jq -r '.message.content | split("\n")[0]' | grep -q '^\[pr-review-dispatch\]' && echo ok)"
has "run reports the send" "$out" "send  acme/widget#42"

# --- the job after delivery -------------------------------------------------

printf 'job bookkeeping\n'
arrange_and_deliver 2
eq "pending is emptied" "0" "$(job '.pending | length')"
eq "status is delivered" "delivered" "$(job .status)"
eq "deliveredVia names the socket" "socket" "$(job .deliveredVia)"
eq "deliveredCount counts the items" "2" "$(job .deliveredCount)"
# seen is the WATCHER's high-water. Clearing it here would make the next poll
# queue the same feedback again, forever.
eq "seen survives delivery" "review:11 issue:31" "$(job '.seen | join(" ")')"

printf 'prompt file\n'
arrange_and_deliver 3
body=$(cat "$STATE/jobs/acme__widget__42.prompt.md")
# shellcheck disable=SC2016  # the backticks are literal test data, not a subshell
has "carries the multi-line body verbatim" "$body" 'line two with `backticks` and "quotes"'
has "carries the inline path and line" "$body" 'a/b.ts:9'
has "names both authors" "$body" "bob"
has "names the review state" "$body" "CHANGES_REQUESTED"
has "an empty body is called out, not left blank" "$body" "the verdict is the message"

# --- busy is not a gate -----------------------------------------------------
# The inversion. The old program refused anything that was not positively
# `idle`, because typing into a busy pane was unsafe. Claude Code reads a socket
# message between tool calls, so a busy session is a normal target and the
# status field is not consulted at all.

printf 'busy is not a gate\n'
reset
PID=$(spawn_holder); WIRE="$TMP/wire-2"; SOCKP="$TMP/s2.sock"
listen "$SOCKP" "$WIRE" || no "listener came up"
session live "$PID" "$WT" "$SOCKP" 100 busy
make_job
out=$(run); settle "$WIRE"
eq "a busy session is delivered to" "delivered" "$(job .status)"
eq "the line still arrived" "user" "$(jq -r .type < "$WIRE" 2>/dev/null)"

# An unrecognised status is not a reason to hold either -- there is nothing to
# recognise. This is the opposite of the old rule and is stated on purpose.
reset
PID=$(spawn_holder); WIRE="$TMP/wire-3"; SOCKP="$TMP/s3.sock"
listen "$SOCKP" "$WIRE" || no "listener came up"
session live "$PID" "$WT" "$SOCKP" 100 some-future-status
make_job
run >/dev/null; settle "$WIRE"
eq "an unknown status is delivered to" "delivered" "$(job .status)"

# --- liveness ---------------------------------------------------------------

printf 'liveness\n'
# A registry file outlives the process that wrote it. Ranking is newest-first,
# so a stale file left by a dead session in the same worktree would shadow the
# live one and hold its job forever. Both entries here name the same worktree
# and the dead one is NEWER.
reset
DEAD=$(spawn_holder); kill "$DEAD" 2>/dev/null; wait "$DEAD" 2>/dev/null
ALIVE=$(spawn_holder); WIRE="$TMP/wire-4"; SOCKP="$TMP/s4.sock"; DEADSOCK="$TMP/s4dead.sock"
listen "$SOCKP" "$WIRE" || no "listener came up"
listen "$DEADSOCK" "$TMP/wire-4dead" || no "dead listener came up"
session alive "$ALIVE" "$WT" "$SOCKP" 100
session stale "$DEAD" "$WT" "$DEADSOCK" 999
make_job
run >/dev/null; settle "$WIRE"
eq "a dead newer session does not shadow a live one" "delivered" "$(job .status)"
eq "the live session got it" "user" "$(jq -r .type < "$WIRE" 2>/dev/null)"
eq "the dead session's socket got nothing" "" "$(cat "$TMP/wire-4dead" 2>/dev/null)"

# A session whose socket path names a file that is not there is not a target.
reset
PID=$(spawn_holder)
session nosock "$PID" "$WT" "$TMP/absent.sock" 100
make_job
out=$(run)
eq "a session with no socket holds" "pending" "$(job .status)"
eq "and keeps its items" "2" "$(job '.pending | length')"
has "and says why" "$out" "no live session"
# One session missing its socket file is ordinary, so this must NOT raise the
# schema alarm below -- the entry does carry the field.
case "$out" in
  *messagingSocketPath*) no "a missing socket file does not raise the schema alarm" "[$out]" ;;
  *) ok "a missing socket file does not raise the schema alarm" ;;
esac

# The registry field disappearing is the failure that would otherwise be
# invisible: the list comes back empty, which looks exactly like "nothing is
# running", so every job holds as "no live session" and the pipeline stops for
# good in silence. Entries existing while none carries the field is the shape
# that tells the two apart.
reset
PID=$(spawn_holder)
jq -n --argjson pid "$PID" --arg cwd "$WT" \
  '{pid:$pid, sessionId:"s", name:"s", cwd:$cwd, kind:"interactive",
    startedAt:100, status:"idle", inboxSocket:"/renamed/away.sock"}' > "$SESS/renamed.json"
make_job
out=$(run)
eq "a renamed socket field still holds the job" "pending" "$(job .status)"
has "it names the field" "$out" "messagingSocketPath"
has "it says delivery is dead, not just this job" "$out" "Nothing can be delivered"
has "it names both causes rather than asserting one" "$out" "bare mode"

# --- worktree ownership -----------------------------------------------------
# The longest-prefix rule from pr-review-common.sh, which nesting makes
# load-bearing: `gw` puts every worktree under <checkout>/git-worktrees/, so
# containment alone would let the outer checkout claim every session below it.

printf 'worktree ownership\n'
reset
PID=$(spawn_holder); WIRE="$TMP/wire-5"; SOCKP="$TMP/s5.sock"
listen "$SOCKP" "$WIRE" || no "listener came up"
session inner "$PID" "$WT" "$SOCKP" 100
make_job "$REPO"   # the job is on the OUTER checkout
out=$(run)
eq "a session in an inner worktree does not answer for the outer one" "pending" "$(job .status)"
eq "nothing was sent" "" "$(cat "$WIRE" 2>/dev/null)"

# A cwd DEEPER than the worktree root still belongs to it.
reset
PID=$(spawn_holder); WIRE="$TMP/wire-6"; SOCKP="$TMP/s6.sock"
mkdir -p "$WT/src/deep"
listen "$SOCKP" "$WIRE" || no "listener came up"
session deep "$PID" "$WT/src/deep" "$SOCKP" 100
make_job
run >/dev/null; settle "$WIRE"
eq "a cwd below the worktree root still belongs to it" "delivered" "$(job .status)"

# --- dry run ----------------------------------------------------------------

printf 'dry run\n'
reset
PID=$(spawn_holder); WIRE="$TMP/wire-7"; SOCKP="$TMP/s7.sock"
listen "$SOCKP" "$WIRE" || no "listener came up"
session live "$PID" "$WT" "$SOCKP" 100
make_job
out=$(run --dry-run)
has "reports what it would send" "$out" "send  acme/widget#42"
eq "sends nothing" "" "$(cat "$WIRE" 2>/dev/null)"
eq "leaves the job queued" "pending" "$(job .status)"
eq "writes no prompt file" "absent" "$([ -f "$STATE/jobs/acme__widget__42.prompt.md" ] || echo absent)"

# --- no session at all ------------------------------------------------------

printf 'no live session\n'
reset
make_job
out=$(run)
eq "holds by default" "pending" "$(job .status)"
has "names the opt-in" "$out" "PR_REVIEW_DISPATCH_RESUME=1"
eq "resume was not attempted" "absent" "$([ -f "$TMP/resume.log" ] || echo absent)"

reset
make_job
out=$(RESUME=1 run)
eq "resumes when asked" "delivered" "$(job .status)"
eq "and says so" "resume" "$(job .deliveredVia)"
has "passes the session id to claude" "$(cat "$TMP/resume.log")" "--resume sess-1"

# A failed resume must leave the job queued -- it is the only copy.
reset
make_job
: > "$TMP/resume.fail"
out=$(RESUME=1 run)
eq "a failed resume holds the job" "pending" "$(job .status)"
has "and says so" "$out" "claude --bg --resume failed"

# --- empty queue ------------------------------------------------------------

# --- bookkeeping that cannot be written -------------------------------------
# The worst outcome available: the message is already gone, so a job that cannot
# be marked is re-sent on every subsequent run -- every 30s under launchd,
# forever, into somebody's live session. Nothing can prevent it (recording
# "delivered" anywhere means writing to the state directory that just refused a
# write), so the contract is that it is reported loudly rather than swallowed.

printf 'unmarkable job\n'
reset
PID=$(spawn_holder); WIRE="$TMP/wire-8"; SOCKP="$TMP/s8.sock"
listen "$SOCKP" "$WIRE" || no "listener came up"
session live "$PID" "$WT" "$SOCKP" 100
make_job
chmod 500 "$STATE/jobs"          # writable job file, unwritable directory
out=$(run 2>&1); settle "$WIRE"
chmod 700 "$STATE/jobs"
eq "the message still went out" "user" "$(jq -r .type < "$WIRE" 2>/dev/null)"
has "the failure is reported" "$out" "could not be marked"
has "it names the consequence" "$out" "WILL be sent again"
eq "no .tmp file is left behind" "" "$(ls "$STATE"/jobs/*.tmp 2>/dev/null)"

printf 'empty queue\n'
reset
out=$(run); rc=$?
eq "exits 0 with nothing to do" "0" "$rc"
eq "and says nothing" "" "$out"

# Silence on an idle tick has to hold even when the registry is broken, and this
# is a real consequence rather than tidiness: launchd runs this every 30s with
# stdout and stderr going to one log file, and these diagnostics are per-run, not
# per-job. Emitting them on empty ticks would write thousands of lines a day and
# bury the occurrence that matters.
reset
PID=$(spawn_holder)
jq -n --argjson pid "$PID" --arg cwd "$WT" \
  '{pid:$pid, sessionId:"s", name:"s", cwd:$cwd, kind:"interactive",
    startedAt:100, status:"idle", inboxSocket:"/renamed/away.sock"}' > "$SESS/renamed.json"
out=$(run)
eq "a broken registry stays quiet while the queue is empty" "" "$out"

# Same for the missing-directory warning, which is also per-run.
reset
out=$(CLAUDE_SESSIONS_DIR="$TMP/no-such-dir" PATH="$STUB:$PATH" \
  PR_REVIEW_WATCH_STATE_DIR="$STATE" "$DISPATCH" 2>&1)
eq "a missing registry dir stays quiet while the queue is empty" "" "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
