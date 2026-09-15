#!/bin/bash
# Exercises bin/pr-review-watch, the detect-and-queue half of the review
# pipeline. Every failure mode here is silent: the script's whole output on a
# quiet poll is nothing at all, so a broken filter looks exactly like "no
# reviews arrived". That is why the assertions are on the queued job files
# rather than on the exit status.
#
# Only the network-facing commands are stubbed -- gh, ghq and claude.
# git is real and so are the worktrees, because
# worktree_for_branch's contract is what git actually reports, and a stubbed git
# would keep passing if that changed.
#
# The gh stub deliberately APPLIES the --jq expression it is given rather than
# returning a pre-shaped answer. Those expressions are where the silent bugs
# live: `select($reasons | index(.reason))` reads `.reason` against the array,
# not the notification, and matches nothing -- caught only because the real
# expression ran against real GitHub-shaped fixtures.
#
# Written for bash 3.2 (/bin/bash on macOS): no mapfile, no associative arrays.
set -uo pipefail

WATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-review-watch"

pass=0
fail=0

ok() {
  pass=$((pass + 1))
  printf '  ok   %s\n' "$1"
}
no() {
  fail=$((fail + 1))
  printf '  FAIL %s\n' "$1"
  [ $# -gt 1 ] && printf '       %s\n' "$2"
}

eq() { # eq <label> <want> <got>
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "want=[$2] got=[$3]"; fi
}

TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null; /bin/rm -rf "$TMP"' EXIT
# macOS hands back /var/... while git reports /private/var/...; without :A-style
# resolution every path comparison below is against the wrong prefix.
TMP=$(cd "$TMP" && pwd -P)

FIX="$TMP/fixtures"
STUB="$TMP/stub"
mkdir -p "$FIX" "$STUB"

# --- stubs ------------------------------------------------------------------

cat >"$STUB/gh" <<'EOF'
#!/bin/bash
# Minimal gh api stub. Maps an endpoint to a fixture file of raw GitHub-shaped
# JSON, then applies --jq to it exactly as gh would, so the caller's jq
# expressions are the ones under test.
set -uo pipefail
[ "${1:-}" = "api" ] || { echo "gh stub: unsupported subcommand ${1:-}" >&2; exit 2; }
shift
include=0; jqexpr=""; endpoint=""; cond=0
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--include) include=1; shift ;;
    --paginate) shift ;;
    --jq) jqexpr=$2; shift 2 ;;
    -H|--header) case "$2" in If-Modified-Since:*) cond=1 ;; esac; shift 2 ;;
    -*) shift ;;
    *) endpoint=$1; shift ;;
  esac
done
case "$endpoint" in
  user) fixture="$FIX/user.json" ;;
  notifications*)
    if [ "$cond" -eq 1 ] && [ -f "$FIX/not-modified" ]; then
      printf 'HTTP/2.0 304 Not Modified\r\nX-Poll-Interval: 60\r\n\r\n'
      exit 1
    fi
    if [ "$include" -eq 1 ]; then
      printf 'HTTP/2.0 200 OK\r\nLast-Modified: %s\r\nX-Poll-Interval: 60\r\n\r\n' \
        "$(cat "$FIX/last-modified")"
      cat "$FIX/notifications.json"
      exit 0
    fi
    fixture="$FIX/notifications.json" ;;
  */pulls/*/reviews) fixture="$FIX/reviews.json" ;;
  */pulls/*/comments) fixture="$FIX/review_comments.json" ;;
  */issues/*/comments) fixture="$FIX/issue_comments.json" ;;
  */pulls/*) fixture="$FIX/pull.json" ;;
  *) echo "gh stub: no fixture for $endpoint" >&2; exit 1 ;;
esac
[ -f "$fixture" ] || { echo "gh stub: missing $fixture" >&2; exit 1; }
if [ -n "$jqexpr" ]; then jq -r "$jqexpr" < "$fixture"; else cat "$fixture"; fi
EOF

cat >"$STUB/ghq" <<'EOF'
#!/bin/bash
# ghq list -p -e github.com/<owner>/<name>
set -uo pipefail
for a in "$@"; do
  case "$a" in github.com/*) [ -f "$FIX/ghq-$(printf '%s' "$a" | tr '/' '_')" ] \
    && cat "$FIX/ghq-$(printf '%s' "$a" | tr '/' '_')"; exit 0 ;;
  esac
done
exit 0
EOF

cat >"$STUB/claude" <<'EOF'
#!/bin/bash
set -uo pipefail
[ "${1:-}" = "agents" ] && cat "$FIX/agents.json" || exit 1
EOF

chmod +x "$STUB"/*

# --- a real repository with the branch checked out in a worktree -------------

REPO="$TMP/repo"
WT="$TMP/wt"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feature/x "$WT" >/dev/null 2>&1
printf '%s' "$REPO" >"$FIX/ghq-github.com_acme_widget"

printf '{"login":"alice"}\n' >"$FIX/user.json"
printf 'Mon, 07 Sep 2026 10:00:10 GMT' >"$FIX/last-modified"

cat >"$FIX/pull.json" <<EOF
{"head":{"ref":"feature/x"},"html_url":"https://github.com/acme/widget/pull/42","title":"a title"}
EOF

cat >"$FIX/agents.json" <<EOF
[{"pid":1,"cwd":"$WT","kind":"interactive","sessionId":"sess-1","startedAt":1,"status":"idle"}]
EOF

# One PullRequest notification plus two that must be ignored: a CheckSuite (a red
# build is not review feedback) and a PullRequest whose reason is ci_activity.
cat >"$FIX/notifications.json" <<'EOF'
[
 {"reason":"author","updated_at":"2026-09-07T10:00:00Z",
  "repository":{"full_name":"acme/widget"},
  "subject":{"type":"PullRequest","title":"a title","url":"https://api.github.com/repos/acme/widget/pulls/42"}},
 {"reason":"ci_activity","updated_at":"2026-09-07T10:00:00Z",
  "repository":{"full_name":"acme/widget"},
  "subject":{"type":"CheckSuite","title":"build failed","url":null}},
 {"reason":"ci_activity","updated_at":"2026-09-07T10:00:00Z",
  "repository":{"full_name":"acme/widget"},
  "subject":{"type":"PullRequest","title":"a title","url":"https://api.github.com/repos/acme/widget/pulls/99"}}
]
EOF

# submitted_at null = a PENDING review: a draft only its author can see.
cat >"$FIX/reviews.json" <<'EOF'
[
 {"id":11,"user":{"login":"bob"},"state":"COMMENTED","body":"old thought","submitted_at":"2026-09-01T00:00:00Z"},
 {"id":12,"user":{"login":"bob"},"state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-09-07T10:00:05Z"},
 {"id":13,"user":{"login":"bob"},"state":"PENDING","body":"still drafting","submitted_at":null},
 {"id":14,"user":{"login":"bob"},"state":"APPROVED","body":"","submitted_at":"2026-09-07T10:00:06Z"}
]
EOF

cat >"$FIX/review_comments.json" <<'EOF'
[
 {"id":21,"user":{"login":"bob"},"path":"a.ts","line":10,"original_line":10,"body":"rename this","created_at":"2026-09-07T10:00:05Z"},
 {"id":22,"user":{"login":"alice"},"path":"a.ts","line":11,"original_line":11,"body":"my own reply","created_at":"2026-09-07T10:00:07Z"}
]
EOF

cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":31,"user":{"login":"coderabbitai[bot]"},"body":"nit: typo","created_at":"2026-09-07T10:00:08Z"}
]
EOF

# --- driver -----------------------------------------------------------------

STATE="$TMP/state"

run() { # run [args...] -> stdout+stderr
  PATH="$STUB:$PATH" FIX="$FIX" \
    PR_REVIEW_WATCH_STATE_DIR="$STATE" \
    PR_REVIEW_WATCH_EXTRA_REPOS="" \
    "$WATCH" "$@" 2>&1
}

job() { jq -r "$1" "$STATE/jobs/acme__widget__42.json" 2>/dev/null; }

echo "-- first poll: history is seeded, only post-cutoff feedback is queued --"
out=$(run)

eq 'job file created' 'yes' "$([ -f "$STATE/jobs/acme__widget__42.json" ] && echo yes || echo no)"
eq 'branch resolved' 'feature/x' "$(job .branch)"
eq 'worktree resolved' "$WT" "$(job .worktree)"
eq 'session resolved from claude agents --json' 'sess-1' "$(job .sessionId)"
eq 'pr number is a number' 'number' "$(job '.pr|type')"

# review 11 predates the notification, so it is history: seen, never pending.
eq 'pre-cutoff review seeded as seen, not queued' 'false' "$(job '[.pending[].id]|index("review:11")!=null')"
eq 'pre-cutoff review is in seen' 'true' "$(job '[.seen[]]|index("review:11")!=null')"

eq 'wordless CHANGES_REQUESTED is queued' 'true' "$(job '[.pending[].id]|index("review:12")!=null')"
eq 'wordless APPROVED is not queued' 'false' "$(job '[.pending[].id]|index("review:14")!=null')"
eq 'PENDING (unsubmitted) review is not queued' 'false' "$(job '[.pending[].id]|index("review:13")!=null')"
eq 'inline comment is queued' 'true' "$(job '[.pending[].id]|index("inline:21")!=null')"
eq 'own comment is never queued' 'false' "$(job '[.pending[].id]|index("inline:22")!=null')"
eq 'bot conversation comment is queued' 'true' "$(job '[.pending[].id]|index("issue:31")!=null')"
eq 'pending is ordered oldest first' 'true' "$(job '[.pending[].at] == ([.pending[].at]|sort)')"

# The ci_activity PullRequest (#99) must not have produced a second job: a red
# build is not review feedback, and routing it would wake a session per flake.
eq 'ci_activity PR is not queued' '1' "$(find "$STATE/jobs" -name '*.json' | wc -l | tr -d ' ')"

eq 'Last-Modified stored after the batch' 'Mon, 07 Sep 2026 10:00:10 GMT' "$(cat "$STATE/poll.last-modified")"

echo "-- re-poll with the same data queues nothing (the seen set is the high-water) --"
before=$(job '.pending|length')
run >/dev/null
eq 'pending unchanged on re-poll' "$before" "$(job '.pending|length')"

echo "-- a review arriving while the session is busy ACCUMULATES, never replaces --"
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":31,"user":{"login":"coderabbitai[bot]"},"body":"nit: typo","created_at":"2026-09-07T10:00:08Z"},
 {"id":32,"user":{"login":"bob"},"body":"one more thing","created_at":"2026-09-07T10:05:00Z"}
]
EOF
run >/dev/null
eq 'new item appended' 'true' "$(job '[.pending[].id]|index("issue:32")!=null')"
eq 'earlier item still owed' 'true' "$(job '[.pending[].id]|index("issue:31")!=null')"
eq 'pending grew by exactly one' "$((before + 1))" "$(job '.pending|length')"

echo "-- 304 short-circuits: no fetch, no write --"
touch "$FIX/not-modified"
sig_before=$(job '.updatedAt')
out=$(run)
eq '304 produces no output' '' "$out"
eq '304 leaves the job untouched' "$sig_before" "$(job .updatedAt)"
/bin/rm -f "$FIX/not-modified"

echo "-- --force ignores the stored Last-Modified --"
touch "$FIX/not-modified"
run --force >/dev/null
eq '--force still reaches the API' "$((before + 1))" "$(job '.pending|length')"
/bin/rm -f "$FIX/not-modified"

echo "-- --pr adopts a PR with no notification at all --"
# GitHub never notifies you about your own comments, so this is the only path
# that can be exercised solo -- and the only way to pick up a PR whose review
# predates the tool. It must NOT seed history as seen the way first sight does,
# or asking for a PR by name would queue nothing.
STATE="$TMP/state3"
: >"$FIX/not-modified" # prove the notification poll is skipped entirely
out=$(run --pr acme/widget#42)
eq 'queues despite the 304' 'yes' "$(printf '%s' "$out" | grep -q '^queue acme/widget#42' && echo yes || echo no)"
eq 'queues the pre-cutoff review too' 'true' "$(job '[.pending[].id]|index("review:11")!=null')"
eq 'still drops own comments' 'false' "$(job '[.pending[].id]|index("inline:22")!=null')"
eq 'leaves Last-Modified alone' 'no' "$([ -f "$STATE/poll.last-modified" ] && echo yes || echo no)"
out=$(run --pr 'nonsense')
eq 'rejects a malformed --pr' 'yes' "$(printf '%s' "$out" | grep -q 'owner/repo#number' && echo yes || echo no)"
/bin/rm -f "$FIX/not-modified"

echo "-- nested worktrees: the outer checkout must not claim an inner session --"
# `gw` puts every worktree under <checkout>/git-worktrees/, so the main checkout
# is a string prefix of all of them. Matching a session by containment alone made
# a PR built from the main checkout resolve to whichever nested worktree had the
# newest session -- an unrelated branch. Measured on the real machine before the
# fix: worktree ~/dotfiles matched four sessions and picked one on another branch.
MAIN_BRANCH=$(git -C "$REPO" symbolic-ref --short HEAD)
git -C "$REPO" worktree add -q -b feature/nested "$REPO/git-worktrees/nested" >/dev/null 2>&1
cat >"$FIX/pull.json" <<EOF
{"head":{"ref":"$MAIN_BRANCH"},"html_url":"https://github.com/acme/widget/pull/42","title":"a title"}
EOF
# The only session sits in the NESTED worktree, not in the checkout the PR is on.
cat >"$FIX/agents.json" <<EOF
[{"pid":9,"cwd":"$REPO/git-worktrees/nested","kind":"interactive","sessionId":"nested-sess","startedAt":9,"status":"idle"}]
EOF
STATE="$TMP/state4"
run --pr acme/widget#42 >/dev/null
eq 'the PR resolves to the outer checkout' "$REPO" "$(job .worktree)"
eq 'and claims no session at all' 'null' "$(job '.sessionId')"

# The same layout, with a session actually in the outer checkout, must resolve.
cat >"$FIX/agents.json" <<EOF
[{"pid":9,"cwd":"$REPO/git-worktrees/nested","kind":"interactive","sessionId":"nested-sess","startedAt":9,"status":"idle"},
 {"pid":10,"cwd":"$REPO","kind":"interactive","sessionId":"outer-sess","startedAt":10,"status":"idle"}]
EOF
STATE="$TMP/state5"
run --pr acme/widget#42 >/dev/null
eq 'the outer session is picked, not the newer nested one' 'outer-sess' "$(job .sessionId)"

# And a cwd deeper than the worktree root still belongs to that worktree.
cat >"$FIX/pull.json" <<'EOF'
{"head":{"ref":"feature/nested"},"html_url":"https://github.com/acme/widget/pull/42","title":"a title"}
EOF
cat >"$FIX/agents.json" <<EOF
[{"pid":11,"cwd":"$REPO/git-worktrees/nested/src/deep","kind":"interactive","sessionId":"deep-sess","startedAt":11,"status":"idle"}]
EOF
STATE="$TMP/state6"
run --pr acme/widget#42 >/dev/null
eq 'a session in a subdirectory still counts' 'deep-sess' "$(job .sessionId)"

# Restore the fixtures the remaining cases expect.
cat >"$FIX/pull.json" <<'EOF'
{"head":{"ref":"feature/x"},"html_url":"https://github.com/acme/widget/pull/42","title":"a title"}
EOF
cat >"$FIX/agents.json" <<EOF
[{"pid":1,"cwd":"$WT","kind":"interactive","sessionId":"sess-1","startedAt":1,"status":"idle"}]
EOF

echo "-- no worktree for the branch means no job to deliver --"
STATE="$TMP/state2"
git -C "$REPO" worktree remove --force "$WT"
out=$(run)
eq 'reports the reason' 'yes' "$(printf '%s' "$out" | grep -q 'not checked out in any worktree' && echo yes || echo no)"
eq 'writes no job' '0' "$(find "$STATE/jobs" -name '*.json' | wc -l | tr -d ' ')"

echo "-- first sight: a notification that LAGS its own review still queues it --"
# A notification thread is one row per PR, and its updated_at is bumped by ANY
# activity on that PR -- a check suite finishing, a push -- not only by the review
# being routed. So the notification is routinely NEWER than the review that
# triggered it, and seeding history against it files that review as history:
# nothing is queued, silently, and no later poll can recover it because the item
# only gets older. Measured on eversteel/tetsunavi-monorepo#6989 -- review
# submitted 02:13:51Z, notification 02:15:31Z, 100s later -- where all 9 items
# including the triggering review were classified as history.
#
# The first-sight cutoff is therefore the PREVIOUS poll's Last-Modified, the
# value the conditional request was made against: everything the poll returns is
# by definition newer than it, and no amount of thread-bumping can move it.
cat >"$FIX/pull.json" <<EOF
{"head":{"ref":"feature/x"},"html_url":"https://github.com/acme/widget/pull/42","title":"a title"}
EOF
cat >"$FIX/agents.json" <<EOF
[{"pid":1,"cwd":"$WT","kind":"interactive","sessionId":"sess-1","startedAt":1,"status":"idle"}]
EOF
# The previous case removed it; the branch itself survived the removal. A failure
# here would surface as an unrelated assertion failure three lines down, so it is
# fatal rather than silenced -- the same reason bin/lint-shell refuses to report
# ok on a failed listing.
git -C "$REPO" worktree add -q "$WT" feature/x ||
  {
    no 'setup: could not re-add the feature/x worktree'
    exit 1
  }
# updated_at is 115s AFTER review 12, the shape the live API actually returns.
#
# The cutoff must be the Last-Modified this poll was made CONDITIONAL ON, never
# the one it receives back. That is pinned here rather than stated: the response
# carries 10:00:10, which is later than review 12 at 10:00:05, so an
# implementation reading the fresh value files the review as history and the
# first assertion below goes red.
cat >"$FIX/notifications.json" <<'EOF'
[
 {"reason":"author","updated_at":"2026-09-07T10:02:00Z",
  "repository":{"full_name":"acme/widget"},
  "subject":{"type":"PullRequest","title":"a title","url":"https://api.github.com/repos/acme/widget/pulls/42"}}
]
EOF
STATE="$TMP/state7"
mkdir -p "$STATE"
printf 'Mon, 07 Sep 2026 09:59:00 GMT' >"$STATE/poll.last-modified"
run >/dev/null
eq 'the lagged review is queued, not swallowed' 'true' "$(job '[.pending[].id]|index("review:12")!=null')"
eq 'the lagged inline comment is queued too' 'true' "$(job '[.pending[].id]|index("inline:21")!=null')"
# The cutoff must still seed real history: review 11 is from 2026-09-01, long
# before the previous poll, so adopting this PR must not dump it into the prompt.
eq 'history older than the previous poll is still seeded' 'false' "$(job '[.pending[].id]|index("review:11")!=null')"
eq 'and that history is in seen' 'true' "$(job '[.seen[]]|index("review:11")!=null')"

echo "-- an item exactly AT the cutoff is owed, not history --"
# The comparison is `select(.at < $cutoff)`, strict by design: the previous poll
# saw everything UP TO that instant, so an item stamped with the instant itself
# has not been seen. One character (`<` for `<=`) inverts that, and the only
# symptom is a review that never arrives.
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":33,"user":{"login":"bob"},"body":"right on the boundary","created_at":"2026-09-07T09:59:00Z"}
]
EOF
STATE="$TMP/state7b"
mkdir -p "$STATE"
printf 'Mon, 07 Sep 2026 09:59:00 GMT' >"$STATE/poll.last-modified"
run >/dev/null
eq 'an item stamped exactly at the cutoff is queued' 'true' "$(job '[.pending[].id]|index("issue:33")!=null')"

echo "-- an unparseable stored Last-Modified falls back, it does not kill the poll --"
# mkdir can succeed while a write fails, and a file written by an older version
# need not be an HTTP date at all. jq's strptime exits non-zero on one, and a
# poller that dies here stops delivering for good with nothing saying why -- the
# same silent-forever shape as a lock that is never stolen.
#
# Note what a bare "no error was printed" assertion would be worth here: the
# script sends jq's stderr to /dev/null, so no message ever reaches the caller
# whatever happens. The run has to be judged by what it QUEUED.
#
# This fixture is local to the case: the only item newer than the notification is
# issue 34, so a job file existing at all proves the poll ran to completion, and
# an unparsed date leaking through as a literal would sort every ISO timestamp
# below it and queue nothing.
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":34,"user":{"login":"bob"},"body":"after the notification","created_at":"2026-09-07T10:05:00Z"}
]
EOF
STATE="$TMP/state8"
mkdir -p "$STATE"
printf 'not a date' >"$STATE/poll.last-modified"
run >/dev/null
eq 'the poll runs to completion and queues' 'true' "$(job '[.pending[].id]|index("issue:34")!=null')"
eq 'and falls back to the notification cutoff' 'false' "$(job '[.pending[].id]|index("review:11")!=null')"

echo "-- --force sends no conditional request, so it falls back too --"
# --force deliberately drops the If-Modified-Since header, which leaves no
# previous poll to anchor on. Documented in pr-review-watch.md, so it is pinned:
# the stored value must be ignored for the cutoff exactly as it is for the
# request, or --force would seed history against a date it never sent.
STATE="$TMP/state9"
mkdir -p "$STATE"
printf 'Mon, 07 Sep 2026 09:59:00 GMT' >"$STATE/poll.last-modified"
run --force >/dev/null
eq 'the stored value does not become the cutoff' 'false' "$(job '[.pending[].id]|index("review:12")!=null')"
eq 'the post-notification item is still queued' 'true' "$(job '[.pending[].id]|index("issue:34")!=null')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
