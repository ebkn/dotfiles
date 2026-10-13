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
include=0; jqexpr=""; endpoint=""; cond=0; paginate=0
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--include) include=1; shift ;;
    --paginate) paginate=1; shift ;;
    --jq) jqexpr=$2; shift 2 ;;
    -H|--header) case "$2" in If-Modified-Since:*) cond=1 ;; esac; shift 2 ;;
    -*) shift ;;
    *) endpoint=$1; shift ;;
  esac
done
# Every request is logged with whether it was conditional, so a case can assert
# what was ASKED, not only what came back.
printf '%s cond=%s\n' "$endpoint" "$cond" >>"$FIX/gh.log"
case "$endpoint" in
  user) fixture="$FIX/user.json" ;;
  notifications*)
    # A status other than 200/304, or no response at all, on request.
    if [ -f "$FIX/notifications-status" ]; then
      printf 'HTTP/2.0 %s Error\r\n\r\n{}\n' "$(cat "$FIX/notifications-status")"
      exit 1
    fi
    [ -f "$FIX/no-response" ] && exit 1
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
  */pulls/*/reviews)
    # A transient failure on one of the three item endpoints, on request.
    [ -f "$FIX/fail-reviews" ] && exit 1
    fixture="$FIX/reviews.json" ;;
  */pulls/*/comments) fixture="$FIX/review_comments.json" ;;
  */issues/*/comments) fixture="$FIX/issue_comments.json" ;;
  */pulls/*) fixture="$FIX/pull.json" ;;
  *) echo "gh stub: no fixture for $endpoint" >&2; exit 1 ;;
esac
[ -f "$fixture" ] || { echo "gh stub: missing $fixture" >&2; exit 1; }
# A list endpoint without --paginate gets its first page only, as GitHub would
# give it -- here a page of one item, so every fixture with more than one spans
# pages. Ignoring the flag instead made a dropped --paginate invisible, while
# for real it hides everything past the 30th item, oldest first: the newest
# feedback on a busy PR.
case "$endpoint" in
  */reviews | */comments)
    if [ "$paginate" -eq 0 ]; then
      jq '.[0:1]' "$fixture" >"$FIX/page1.json"
      fixture="$FIX/page1.json"
    fi ;;
esac
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

# 33 is CodeRabbit's placeholder: posted the moment a push lands, long before
# there is anything to say. It is the SAME comment that is later edited into the
# walkthrough, so only the marker in the body tells the two apart.
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":31,"user":{"login":"coderabbitai[bot]"},"body":"nit: typo","created_at":"2026-09-07T10:00:08Z"},
 {"id":33,"user":{"login":"coderabbitai[bot]"},"body":"<!-- This is an auto-generated comment: summarize by coderabbit.ai -->\n<!-- This is an auto-generated comment: review in progress by coderabbit.ai -->\n\n> [!NOTE]\n> Currently processing new changes in this PR. This may take a few minutes, please wait...\n\n<!-- end of auto-generated comment: review in progress by coderabbit.ai -->","created_at":"2026-09-07T10:00:09Z"},
 {"id":35,"user":{"login":"coderabbitai[bot]"},"body":"<!-- This is an auto-generated comment: review paused by coderabbit.ai -->\n\n> [!NOTE]\n> ## Reviews paused","created_at":"2026-09-07T10:00:09Z"},
 {"id":36,"user":{"login":"coderabbitai[bot]"},"body":"<!-- This is an auto-generated comment: rate limited by coderabbit.ai -->\n\n> [!WARNING]\n> ## Rate limit exceeded","created_at":"2026-09-07T10:00:09Z"},
 {"id":37,"user":{"login":"coderabbitai[bot]"},"body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!NOTE]\n> ## Review skipped","created_at":"2026-09-07T10:00:09Z"}
]
EOF

# --- driver -----------------------------------------------------------------

STATE="$TMP/state"

# EXTRA_REPOS names a directory that does not exist. An empty value is NOT
# "none": the script defaults it with `:-`, so "" meant the developer's real
# ~/dotfiles was consulted on every run. The extra-repos lookup itself is pinned
# in pr-review-common.test.sh.
run() { # run [args...] -> stdout+stderr
  PATH="$STUB:$PATH" FIX="$FIX" \
    PR_REVIEW_WATCH_STATE_DIR="$STATE" \
    PR_REVIEW_WATCH_EXTRA_REPOS="$TMP/no-extra-repos" \
    "$WATCH" "$@" 2>&1
}

job() { jq -r "$1" "$STATE/jobs/acme__widget__42.json" 2>/dev/null; }

# arrange_pr42 <notification-updated_at> -- PR 42 on feature/x, checked out in
# $WT with a session in it, notified once at the given time. The cases from the
# lagged notification on each call this rather than inheriting the fixtures the
# case before them happened to leave behind.
arrange_pr42() {
  cat >"$FIX/pull.json" <<'EOF'
{"head":{"ref":"feature/x"},"html_url":"https://github.com/acme/widget/pull/42","title":"a title"}
EOF
  cat >"$FIX/agents.json" <<EOF
[{"pid":1,"cwd":"$WT","kind":"interactive","sessionId":"sess-1","startedAt":1,"status":"idle"}]
EOF
  cat >"$FIX/notifications.json" <<EOF
[
 {"reason":"author","updated_at":"$1",
  "repository":{"full_name":"acme/widget"},
  "subject":{"type":"PullRequest","title":"a title","url":"https://api.github.com/repos/acme/widget/pulls/42"}}
]
EOF
  printf '%s' "$REPO" >"$FIX/ghq-github.com_acme_widget"
  /bin/rm -f "$FIX/not-modified" "$FIX/notifications-status" "$FIX/no-response" "$FIX/fail-reviews"
  # A failure here would surface as an unrelated assertion failure further
  # down, so it is fatal -- the same reason bin/lint-shell refuses to report ok
  # on a failed listing.
  if [ ! -d "$WT" ]; then
    git -C "$REPO" worktree add -q "$WT" feature/x || {
      no 'setup: could not re-add the feature/x worktree'
      exit 1
    }
  fi
}

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

# What dispatch renders into the prompt. Its own suite builds jobs by hand, so
# a mapping broken here -- an inline comment arriving with no file or line --
# would pass both suites; dispatch prints a null location as nothing at all.
eq 'an inline item carries its kind, file and line' 'inline bob a.ts 10' \
  "$(job '.pending[] | select(.id == "inline:21") | "\(.kind) \(.author) \(.path) \(.line)"')"
eq 'a review item carries its verdict and no location' 'review CHANGES_REQUESTED null null' \
  "$(job '.pending[] | select(.id == "review:12") | "\(.kind) \(.state) \(.path) \(.line)"')"
eq 'a conversation item carries its kind and body' 'issue nit: typo' \
  "$(job '.pending[] | select(.id == "issue:31") | "\(.kind) \(.body)"')"
eq 'the job carries the PR url and title' 'https://github.com/acme/widget/pull/42 a title' \
  "$(job '"\(.url) \(.title)"')"

# "a review is running" is not review feedback. It must not reach `seen` either:
# CodeRabbit edits this very comment into the walkthrough, and recording the id
# now would swallow the walkthrough forever.
eq '"review in progress" is not queued' 'false' "$(job '[.pending[].id]|index("issue:33")!=null')"
eq '"review in progress" is not marked seen' 'false' "$(job '[.seen[]]|index("issue:33")!=null')"
# One case per branch of the alternation: a typo in any one of them is otherwise
# invisible, since the others keep the filter looking like it works.
eq 'paused / rate limited / skipped are dropped too' 'false' \
  "$(job '[.pending[].id]|any(. == "issue:35" or . == "issue:36" or . == "issue:37")')"

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
# Something unseen is waiting (issue 40), so the outcome depends on the request
# being conditional. With nothing new in the fixtures, a run that never sent
# If-Modified-Since -- the stub answers 304 only when it arrives -- would fetch,
# find nothing, and pass every assertion here for the wrong reason.
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":31,"user":{"login":"coderabbitai[bot]"},"body":"nit: typo","created_at":"2026-09-07T10:00:08Z"},
 {"id":32,"user":{"login":"bob"},"body":"one more thing","created_at":"2026-09-07T10:05:00Z"},
 {"id":40,"user":{"login":"bob"},"body":"waiting behind the 304","created_at":"2026-09-07T10:10:00Z"}
]
EOF
touch "$FIX/not-modified"
sig_before=$(job '.updatedAt')
out=$(run)
eq '304 produces no output' '' "$out"
eq '304 leaves the job untouched' "$sig_before" "$(job .updatedAt)"
eq '304 fetches nothing, so the waiting comment is not queued' 'false' \
  "$(job '[.pending[].id]|index("issue:40")!=null')"
/bin/rm -f "$FIX/not-modified"

echo "-- --force ignores the stored Last-Modified --"
# A new item only an UNCONDITIONAL request can reach: with not-modified set, any
# request carrying If-Modified-Since gets the 304 and queues nothing, which is
# exactly the regression --force exists to get past.
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":31,"user":{"login":"coderabbitai[bot]"},"body":"nit: typo","created_at":"2026-09-07T10:00:08Z"},
 {"id":32,"user":{"login":"bob"},"body":"one more thing","created_at":"2026-09-07T10:05:00Z"},
 {"id":38,"user":{"login":"bob"},"body":"after the 304","created_at":"2026-09-07T10:06:00Z"}
]
EOF
touch "$FIX/not-modified"
: >"$FIX/gh.log"
run --force >/dev/null
eq '--force polls without If-Modified-Since' 'notifications?all=true&per_page=50 cond=0' \
  "$(grep '^notifications' "$FIX/gh.log")"
eq '--force queues what the 304 would have hidden' 'true' "$(job '[.pending[].id]|index("issue:38")!=null')"
/bin/rm -f "$FIX/not-modified"

echo "-- --pr adopts a PR with no notification at all --"
# GitHub never notifies you about your own comments, so this is the only path
# that can be exercised solo -- and the only way to pick up a PR whose review
# predates the tool. It must NOT seed history as seen the way first sight does,
# or asking for a PR by name would queue nothing.
STATE="$TMP/state3"
# A stored Last-Modified plus not-modified: a notification poll, had one been
# made, would be conditional and get the 304. Without the stored value the poll
# would be unconditional and the 304 branch unreachable.
mkdir -p "$STATE"
printf 'Mon, 07 Sep 2026 09:00:00 GMT' >"$STATE/poll.last-modified"
: >"$FIX/not-modified"
: >"$FIX/gh.log"
out=$(run --pr acme/widget#42)
eq 'makes no notification request at all' '' "$(grep '^notifications' "$FIX/gh.log")"
eq 'queues despite the 304 a poll would have got' 'yes' "$(printf '%s' "$out" | grep -q '^queue acme/widget#42' && echo yes || echo no)"
eq 'queues the pre-cutoff review too' 'true' "$(job '[.pending[].id]|index("review:11")!=null')"
eq 'still drops own comments' 'false' "$(job '[.pending[].id]|index("inline:22")!=null')"
eq 'leaves Last-Modified alone' 'Mon, 07 Sep 2026 09:00:00 GMT' "$(cat "$STATE/poll.last-modified")"
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
# updated_at is 115s AFTER review 12, the shape the live API actually returns.
# (The previous case removed $WT; arrange_pr42 re-adds it.)
#
# The cutoff must be the Last-Modified this poll was made CONDITIONAL ON, never
# the one it receives back. That is pinned here rather than stated: the response
# carries 10:00:10, which is later than review 12 at 10:00:05, so an
# implementation reading the fresh value files the review as history and the
# first assertion below goes red.
arrange_pr42 2026-09-07T10:02:00Z
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
arrange_pr42 2026-09-07T10:02:00Z
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
arrange_pr42 2026-09-07T10:02:00Z
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
# Review 12 (10:00:05) is after the stored value but before the notification;
# issue 34 (10:05:00) is after both.
arrange_pr42 2026-09-07T10:02:00Z
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":34,"user":{"login":"bob"},"body":"after the notification","created_at":"2026-09-07T10:05:00Z"}
]
EOF
STATE="$TMP/state9"
mkdir -p "$STATE"
printf 'Mon, 07 Sep 2026 09:59:00 GMT' >"$STATE/poll.last-modified"
run --force >/dev/null
eq 'the stored value does not become the cutoff' 'false' "$(job '[.pending[].id]|index("review:12")!=null')"
eq 'the post-notification item is still queued' 'true' "$(job '[.pending[].id]|index("issue:34")!=null')"

echo "-- the placeholder edited into a walkthrough is queued then, not swallowed --"
# The whole point of matching the body rather than the id. This re-polls the
# FIRST state dir, the one that dropped issue:33 above without recording it, so
# what is under test is the loop: dropped, absent from `seen`, then queued on the
# next poll under the same id. A fresh state dir would only re-prove that a
# `summarize` body is not noise. Nothing re-notifies about a comment edit, so an
# id-based drop would lose this permanently.
STATE="$TMP/state"
eq 'precondition: the placeholder was never recorded' 'false' "$(job '[.seen[]]|index("issue:33")!=null')"
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":33,"user":{"login":"coderabbitai[bot]"},"body":"<!-- This is an auto-generated comment: summarize by coderabbit.ai -->\n\n## Walkthrough\n\nThe trust policy drops a deleted user.","created_at":"2026-09-07T10:00:09Z"}
]
EOF
run >/dev/null
eq 'walkthrough queued once the placeholder is gone' 'true' "$(job '[.pending[].id]|index("issue:33")!=null')"

# --- the reason filter -------------------------------------------------------
# REASONS is hand-copied from GitHub's docs, and a reason dropped or misspelt
# there means that PR is never queued, silently. One case per entry, plus the
# two excluded on purpose.
echo "-- every listed reason is queued; ci_activity and subscribed are not --"
cat >"$FIX/issue_comments.json" <<'EOF'
[
 {"id":40,"user":{"login":"bob"},"body":"after the notification","created_at":"2026-09-07T10:05:00Z"}
]
EOF
for reason in assign author comment mention review_requested team_mention ci_activity subscribed; do
  arrange_pr42 2026-09-07T10:02:00Z
  jq --arg r "$reason" '.[0].reason = $r' "$FIX/notifications.json" >"$FIX/n.tmp" &&
    mv "$FIX/n.tmp" "$FIX/notifications.json"
  STATE="$TMP/state-reason-$reason"
  run >/dev/null
  case "$reason" in
    ci_activity | subscribed) want=no ;;
    *) want=yes ;;
  esac
  eq "reason $reason: queued=$want" "$want" \
    "$([ -f "$STATE/jobs/acme__widget__42.json" ] && echo yes || echo no)"
done

echo "-- --dry-run reports, and writes neither the job nor the cursor --"
arrange_pr42 2026-09-07T10:02:00Z
STATE="$TMP/state-dry"
out=$(run --dry-run)
eq 'it reports what it would queue' 'yes' "$(printf '%s' "$out" | grep -q '^queue acme/widget#42' && echo yes || echo no)"
eq 'it writes no job' 'no' "$([ -f "$STATE/jobs/acme__widget__42.json" ] && echo yes || echo no)"
# The cursor matters more than the job: advancing it would make the next real
# poll's 304 hide everything the dry run only looked at.
eq 'it does not advance Last-Modified' 'no' "$([ -f "$STATE/poll.last-modified" ] && echo yes || echo no)"

echo "-- --print dumps the queue and polls nothing --"
# Its own queue, arranged here, rather than one an earlier case left behind.
arrange_pr42 2026-09-07T10:02:00Z
STATE="$TMP/state-print"
run >/dev/null
: >"$FIX/gh.log"
out=$(run --print)
eq 'it prints the queued jobs as one array' 'acme/widget#42' "$(printf '%s' "$out" | jq -r '.[] | .repo + "#" + (.pr|tostring)')"
eq 'it makes no request' '' "$(cat "$FIX/gh.log")"
STATE="$TMP/state-print-empty"
eq 'an empty queue prints []' '[]' "$(run --print | jq -c .)"

echo "-- a failed poll dies loudly and keeps the cursor --"
# Advancing the cursor past a poll that was never read would make the next 304
# hide its notifications for good.
arrange_pr42 2026-09-07T10:02:00Z
STATE="$TMP/state-err"
mkdir -p "$STATE"
printf 'Mon, 07 Sep 2026 09:00:00 GMT' >"$STATE/poll.last-modified"
printf '502' >"$FIX/notifications-status"
out=$(run)
rc=$?
eq 'a non-200 exits 1' '1' "$rc"
eq 'and names the status' 'yes' "$(printf '%s' "$out" | grep -q 'returned HTTP 502' && echo yes || echo no)"
eq 'and leaves Last-Modified as it was' 'Mon, 07 Sep 2026 09:00:00 GMT' "$(cat "$STATE/poll.last-modified")"
/bin/rm -f "$FIX/notifications-status"
: >"$FIX/no-response"
out=$(run)
rc=$?
eq 'no response at all exits 1' '1' "$rc"
eq 'and says so' 'yes' "$(printf '%s' "$out" | grep -q 'no response from the notifications API' && echo yes || echo no)"
/bin/rm -f "$FIX/no-response"

echo "-- PRs that cannot be routed are skipped by name --"
arrange_pr42 2026-09-07T10:02:00Z
STATE="$TMP/state-skip"
/bin/rm -f "$FIX/ghq-github.com_acme_widget"
out=$(run)
eq 'no local checkout is reported' 'skip acme/widget#42: no local checkout' "$out"
arrange_pr42 2026-09-07T10:02:00Z
/bin/rm -f "$FIX/pull.json"
out=$(run)
eq 'an unreadable PR is reported' 'skip acme/widget#42: could not read the PR' "$out"
eq 'and neither writes a job' '0' "$(find "$STATE/jobs" -name '*.json' | wc -l | tr -d ' ')"

echo "-- a PR that could not be read keeps the cursor where it was --"
# A failed read is not "nothing new". Advanced past it, the next poll is a 304
# and the review that triggered this one is never looked at again; for a PR
# with no job yet, the next notification's cutoff then files it as history.
# The cursor stays so the next poll returns the same notification and retries.
arrange_pr42 2026-09-07T10:02:00Z
STATE="$TMP/state-unread"
mkdir -p "$STATE"
printf 'Mon, 07 Sep 2026 09:00:00 GMT' >"$STATE/poll.last-modified"
/bin/rm -f "$FIX/pull.json"
run >/dev/null
eq 'an unreadable PR leaves Last-Modified as it was' 'Mon, 07 Sep 2026 09:00:00 GMT' \
  "$(cat "$STATE/poll.last-modified")"
arrange_pr42 2026-09-07T10:02:00Z
: >"$FIX/fail-reviews"
out=$(run)
eq 'unreadable reviews are reported, not taken for none' \
  'skip acme/widget#42: could not read its review feedback' "$out"
eq 'and write no job from the other two endpoints' 'no' \
  "$([ -f "$STATE/jobs/acme__widget__42.json" ] && echo yes || echo no)"
eq 'and leave Last-Modified as it was' 'Mon, 07 Sep 2026 09:00:00 GMT' \
  "$(cat "$STATE/poll.last-modified")"
/bin/rm -f "$FIX/fail-reviews"
run >/dev/null
eq 'the retry queues what the failed poll could not' 'true' \
  "$(job '[.pending[].id]|index("review:12")!=null')"
eq 'and only then advances Last-Modified' 'Mon, 07 Sep 2026 10:00:10 GMT' \
  "$(cat "$STATE/poll.last-modified")"

echo "-- a live lock holder means this run does nothing --"
# launchd fires every 60s whether or not the last run finished; two polls
# interleaving writes to one job file queue a review twice.
arrange_pr42 2026-09-07T10:02:00Z
STATE="$TMP/state-lock"
mkdir -p "$STATE/.lock"
sleep 300 >/dev/null 2>&1 &
holder=$!
printf '%s' "$holder" >"$STATE/.lock/pid"
: >"$FIX/gh.log"
out=$(run)
rc=$?
eq 'it exits 0 silently' '0:' "$rc:$out"
eq 'it makes no request' '' "$(cat "$FIX/gh.log")"
eq "and leaves the holder's lock" "$holder" "$(cat "$STATE/.lock/pid")"
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null

echo "-- an outdated inline comment keeps the line it was left on --"
# Once a push moves the code out from under a comment, GitHub nulls .line and
# keeps .original_line. Without the fallback the comment arrives with no line.
arrange_pr42 2026-09-07T10:02:00Z
cat >"$FIX/review_comments.json" <<'EOF'
[
 {"id":24,"user":{"login":"bob"},"path":"b.ts","line":null,"original_line":7,"body":"stale but real","created_at":"2026-09-07T10:01:00Z"}
]
EOF
STATE="$TMP/state-outdated"
run --pr acme/widget#42 >/dev/null
eq 'an outdated comment falls back to original_line' 'b.ts 7' \
  "$(job '.pending[] | select(.id == "inline:24") | "\(.path) \(.line)"')"

echo "-- a mistyped invocation is refused, never run as a poll --"
# Without the refusal, --dryrun would be a real poll: jobs written, cursor moved.
STATE="$TMP/state-args"
: >"$FIX/gh.log"
out=$(run --dryrun)
rc=$?
eq 'an unknown argument exits 1' '1' "$rc"
eq 'and names it' 'yes' "$(printf '%s' "$out" | grep -q 'unknown argument: --dryrun' && echo yes || echo no)"
eq 'and makes no request' '' "$(cat "$FIX/gh.log")"
out=$(run --pr)
rc=$?
eq '--pr with no value exits 1' '1' "$rc"
eq 'and says what it wants' 'yes' "$(printf '%s' "$out" | grep -q 'owner/repo#number' && echo yes || echo no)"
run --pr nonsense >/dev/null
eq 'a malformed --pr exits 1' '1' "$?"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
