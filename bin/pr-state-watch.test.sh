#!/bin/bash
# Exercises bin/pr-state-watch, the detector that notices a PR of yours can no
# longer merge and queues it for the session on that branch.
#
# Every failure here is silent, in both directions. A detector that never fires
# is indistinguishable from a week with no conflicts; one that fires on every
# pass trains its reader to ignore it. The exit status says nothing about either,
# so the assertions are on the queued job files -- the same discipline
# pr-review-watch.test.sh applies for the same reason.
#
# Only the network-facing commands are stubbed -- gh, ghq and claude. git is
# real and so are the worktrees, because worktree_for_branch's contract is what
# git actually reports.
#
# The gh stub APPLIES the --jq expression it is given rather than returning a
# pre-shaped answer, so the script's own jq is the thing under test. That is not
# caution: jq rebinds `.` inside a pipe, and every filter this pipeline has
# written wrong that way produced an EMPTY RESULT instead of an error.
#
# Written for bash 3.2 (/bin/bash on macOS): no mapfile, no associative arrays.
set -uo pipefail

WATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-state-watch"

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
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "want=[$2] got=[$3]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) no "$1" "[$2] does not contain [$3]" ;; esac }

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
# `gh search prs` and `gh pr list`, both reading a fixture and applying --jq
# exactly as gh would. Each call is appended to $GHLOG so a case can assert on
# the REQUEST SHAPE -- the per-repo cost is the whole reason this program is not
# folded into pr-review-watch, and nothing else would notice it changing.
set -uo pipefail
printf '%s\n' "$*" >>"$GHLOG"
sub=${1:-}; shift
jqexpr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) jqexpr=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$sub" in
  search) fixture="$FIX/search.json" ;;
  pr) fixture="$FIX/prs.json" ;;
  *) echo "gh stub: unsupported subcommand $sub" >&2; exit 2 ;;
esac
[ -f "$fixture" ] || { echo "gh stub: missing $fixture" >&2; exit 1; }
if [ -n "$jqexpr" ]; then jq -r "$jqexpr" <"$fixture"; else cat "$fixture"; fi
EOF

cat >"$STUB/ghq" <<'EOF'
#!/bin/bash
set -uo pipefail
for a in "$@"; do
  case "$a" in github.com/*) f="$FIX/ghq-$(printf '%s' "$a" | tr '/' '_')"
    [ -f "$f" ] && cat "$f"; exit 0 ;;
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
WT="$REPO/git-worktrees/wt"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feature/x "$WT" >/dev/null 2>&1
printf '%s' "$REPO" >"$FIX/ghq-github.com_acme_widget"

cat >"$FIX/search.json" <<'EOF'
[{"number":42,"repository":{"name":"widget","nameWithOwner":"acme/widget"}},
 {"number":43,"repository":{"name":"widget","nameWithOwner":"acme/widget"}}]
EOF

cat >"$FIX/agents.json" <<EOF
[{"pid":1,"cwd":"$WT","kind":"interactive","sessionId":"sess-1","startedAt":1,"status":"idle"}]
EOF

# prs <mergeable> [isDraft] [headRefOid] [branch]
prs() {
  jq -n --arg m "${1:-CONFLICTING}" --argjson d "${2:-false}" \
    --arg oid "${3:-abc1234}" --arg br "${4:-feature/x}" '
    [{number:42, title:"a title", url:"https://github.com/acme/widget/pull/42",
      headRefName:$br, baseRefName:"trunk", headRefOid:$oid,
      mergeable:$m, isDraft:$d}]' >"$FIX/prs.json"
}

STATE="$TMP/state"
JOB="$STATE/jobs/acme__widget__42__conflict.json"

run() {
  : >"$TMP/gh.log"
  PATH="$STUB:$PATH" FIX="$FIX" GHLOG="$TMP/gh.log" \
    PR_REVIEW_WATCH_STATE_DIR="$STATE" \
    PR_REVIEW_WATCH_EXTRA_REPOS="" \
    "$WATCH" "$@" 2>&1
}
job() { jq -r "$1" "$JOB" 2>/dev/null; }

echo "-- a conflicting PR is queued for the session on that branch --"
prs CONFLICTING
out=$(run)

eq 'a job file is written' 'yes' "$([ -f "$JOB" ] && echo yes || echo no)"
# The kind is what the deliverer branches on. Without it the conflict renders as
# review feedback with an empty body -- delivered, plausible, and useless.
eq 'it is marked as a conflict' 'conflict' "$(job .kind)"
eq 'the base branch is carried, not assumed' 'trunk' "$(job .base)"
eq 'the worktree is resolved' "$WT" "$(job .worktree)"
eq 'the session on that worktree is resolved' 'sess-1' "$(job .sessionId)"
eq 'pr number is a number' 'number' "$(job '.pr|type')"
eq 'exactly one pending item' '1' "$(job '.pending|length')"
has 'the run says what cannot merge' "$out" 'feature/x cannot merge into trunk'

# The queue is shared with pr-review-watch, whose job for the same PR is
# acme__widget__42.json. Two detectors writing ONE file would interleave, and
# each would silently drop the other's pending items on the next pass.
eq 'the filename does not collide with a review job on the same PR' 'yes' \
  "$([ ! -f "$STATE/jobs/acme__widget__42.json" ] && echo yes || echo no)"

echo "-- the same conflict is not re-queued on every pass --"
# The core difference from the review path: a conflict is a STATE, not an event.
# It has no id and it persists, so a `seen` set cannot key it and re-announcing
# it every 5 minutes is how a notifier gets muted.
before=$(job .updatedAt)
out=$(run)
eq 'a second pass queues nothing' '' "$(printf '%s' "$out" | grep '^queue' || true)"
eq 'and leaves the job untouched' "$before" "$(job .updatedAt)"

echo "-- a new push that still does not merge IS announced again --"
# The other half of keying on the head oid, and the reason the key is not simply
# "already told them once": the session pushed, the branch still conflicts, and
# that is precisely when it needs to hear so a second time.
prs CONFLICTING false newsha
out=$(run)
has 'the new head re-queues' "$out" 'queue acme/widget#42'
eq 'and the stored head advances' 'newsha' "$(job .conflictHead)"

echo "-- becoming mergeable clears the job --"
prs MERGEABLE false newsha
run >/dev/null
eq 'pending is emptied' '0' "$(job '.pending|length')"
eq 'the status says resolved' 'resolved' "$(job .status)"
# Cleared rather than remembered, and the assertion that matters is the
# behaviour that follows from it: a branch that merges cleanly and then
# conflicts again WITHOUT being pushed to -- because the base moved -- has the
# same head oid as the conflict already reported. Remembering it would make that
# second conflict indistinguishable from the first and drop it silently.
eq 'the conflict head is forgotten' 'null' "$(job .conflictHead)"
prs CONFLICTING false newsha
out=$(run)
has 'so the same head conflicting again is announced' "$out" 'queue acme/widget#42'
eq 'and the job is pending once more' 'pending' "$(job .status)"

# ...and a PR that simply merges cleanly, having never conflicted, is not a PR
# this pipeline has anything to say about.
/bin/rm -f "$JOB"
prs MERGEABLE false newsha
out=$(run)
eq 'a mergeable PR with no job writes none' 'no' "$([ -f "$JOB" ] && echo yes || echo no)"
eq 'and reports nothing' '' "$(printf '%s' "$out" | grep -v '^$' || true)"

echo "-- a conflict that resolves itself before delivery is never delivered --"
prs CONFLICTING false sha-a
run >/dev/null
eq 'queued while conflicting' '1' "$(job '.pending|length')"
prs MERGEABLE false sha-a
run >/dev/null
eq 'and withdrawn once it merges again' '0' "$(job '.pending|length')"

echo "-- UNKNOWN is a third answer, not a synonym for either --"
# GitHub computes mergeability lazily: the first query returns UNKNOWN and
# starts a background job, and a query seconds later returns the real value.
# Verified on a live PR (UNKNOWN, then CONFLICTING, from two calls seconds
# apart). Reading it as "fine" makes the detector go silent; reading it as
# "conflicting" makes it cry wolf.
prs CONFLICTING false sha-u
run >/dev/null
eq 'a conflict is queued first' '1' "$(job '.pending|length')"
prs UNKNOWN false sha-u
out=$(run)
eq 'UNKNOWN does not clear a real conflict' '1' "$(job '.pending|length')"
eq 'and does not mark it resolved' 'pending' "$(job .status)"
has 'the wait is reported rather than silent' "$out" 'still computing'

# ...and on a PR with no job at all, UNKNOWN must not invent one.
/bin/rm -f "$JOB"
out=$(run)
eq 'UNKNOWN queues nothing by itself' 'no' "$([ -f "$JOB" ] && echo yes || echo no)"

echo "-- a draft PR is work in progress, not news --"
# The rm is the Arrange, not tidiness: without it this case passes whenever the
# preceding group happened to leave no job, and stops testing anything the
# moment the groups are reordered.
/bin/rm -f "$JOB"
prs CONFLICTING true sha-d
run >/dev/null
eq 'a conflicting draft writes no job' 'no' "$([ -f "$JOB" ] && echo yes || echo no)"

echo "-- no worktree for the branch means nothing this pipeline can deliver --"
/bin/rm -f "$JOB"
prs CONFLICTING false sha-w other/branch
out=$(run)
eq 'writes no job' 'no' "$([ -f "$JOB" ] && echo yes || echo no)"
has 'and says why' "$out" 'not checked out in any worktree'

echo "-- the request shape is the cost, so it is pinned --"
# One search for every open PR anywhere, then one list per repo. The alternative
# -- walking ghq (77 repos on this machine) and asking each -- is 77 requests for
# the same answer. A regression to per-PR requests would still pass every
# assertion above while quietly multiplying the rate-limit cost.
prs CONFLICTING false sha-r
run >/dev/null
eq 'exactly one search' '1' "$(grep -c '^search prs' "$TMP/gh.log")"
eq 'exactly one list, for the one repo' '1' "$(grep -c '^pr list' "$TMP/gh.log")"
has 'mergeability is asked for in the list itself' "$(cat "$TMP/gh.log")" 'mergeable'
has 'and the head oid alongside it' "$(cat "$TMP/gh.log")" 'headRefOid'

echo "-- --pr checks one PR without the search --"
STATE="$TMP/state-pr"
JOB="$STATE/jobs/acme__widget__42__conflict.json"
# Two conflicting PRs in the one repo, because `gh pr list` returns the whole
# repo whatever was asked for -- the narrowing to one PR is this script's own jq,
# and a filter that quietly matches everything is the failure this pipeline has
# already shipped twice (`select($reasons | index(.reason))`, `startswith(. +
# "/")`). Both produce a wrong result rather than an error, so only asking for
# one PR out of two can catch it.
jq -n '[{number:42, title:"a title", url:"https://github.com/acme/widget/pull/42",
         headRefName:"feature/x", baseRefName:"trunk", headRefOid:"p42",
         mergeable:"CONFLICTING", isDraft:false},
        {number:43, title:"other", url:"https://github.com/acme/widget/pull/43",
         headRefName:"feature/x", baseRefName:"trunk", headRefOid:"p43",
         mergeable:"CONFLICTING", isDraft:false}]' >"$FIX/prs.json"
out=$(run --pr acme/widget#42)
eq 'it queues' 'conflict' "$(job .kind)"
eq 'and it is the requested PR' 'p42' "$(job .conflictHead)"
eq 'the other PR in the same repo is left alone' 'no' \
  "$([ -f "$STATE/jobs/acme__widget__43__conflict.json" ] && echo yes || echo no)"
eq 'and spends no search request' '0' "$(grep -c '^search prs' "$TMP/gh.log")"
out=$(run --pr nonsense)
rc=$?
eq 'a malformed --pr exits non-zero' '1' "$rc"
has 'and says the shape' "$out" 'owner/repo#number'

echo "-- --dry-run writes nothing --"
STATE="$TMP/state-dry"
JOB="$STATE/jobs/acme__widget__42__conflict.json"
prs CONFLICTING false sha-x
out=$(run --dry-run)
has 'it still reports' "$out" 'queue acme/widget#42'
eq 'but writes no job' 'no' "$([ -f "$JOB" ] && echo yes || echo no)"

echo "-- a repository whose PRs cannot be listed is reported, not skipped silently --"
STATE="$TMP/state-listfail"
JOB="$STATE/jobs/acme__widget__42__conflict.json"
: >"$FIX/prs.json"
out=$(run)
has 'it says which repository' "$out" 'skip acme/widget: could not list pull requests'
eq 'and writes nothing' '0' "$(find "$STATE/jobs" -name '*.json' | wc -l | tr -d ' ')"
prs CONFLICTING

echo "-- no local checkout means the PR is not this pipeline's business --"
STATE="$TMP/state-nolocal"
/bin/rm -f "$FIX/ghq-github.com_acme_widget"
out=$(run)
has 'it says so' "$out" 'no local checkout'
eq 'and writes nothing' '0' "$(find "$STATE/jobs" -name '*.json' | wc -l | tr -d ' ')"
printf '%s' "$REPO" >"$FIX/ghq-github.com_acme_widget"

echo "-- the two detectors do not lock each other out --"
# This program takes $STATE_DIR/.state-lock, NOT the watcher's $STATE_DIR/.lock.
# They write disjoint job files, so they have no reason to exclude each other --
# and sharing one lock would mean a review poll that is slow, or wedged behind a
# dead holder, silently cancels every conflict pass for as long as it holds. The
# assertion is on the outcome rather than on the filename: a test for the path
# would still pass if the program merely stopped taking a lock at all.
STATE="$TMP/state-lock"
JOB="$STATE/jobs/acme__widget__42__conflict.json"
mkdir -p "$STATE/jobs" "$STATE/.lock"
printf '%s' "$$" >"$STATE/.lock/pid" # this shell is alive, so it is a real holder
prs CONFLICTING false sha-l
out=$(run)
has "the watcher's lock does not block a conflict pass" "$out" 'queue acme/widget#42'
eq 'and its own lock is released afterwards' 'absent' \
  "$([ -d "$STATE/.state-lock" ] || echo absent)"
eq "the watcher's lock is left alone" "$$" "$(cat "$STATE/.lock/pid")"

echo "-- arguments --"
out=$(run --help)
rc=$?
eq '--help exits 0' '0' "$rc"
has 'it prints the usage section' "$out" 'pr-state-watch --dry-run'
case "$out" in
  *'set -uo'*) no '--help stops before the code' "[$out]" ;;
  *) ok '--help stops before the code' ;;
esac
out=$(run --nonsense)
rc=$?
eq 'an unknown argument exits non-zero' '1' "$rc"
has 'and names it' "$out" 'unknown argument: --nonsense'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
