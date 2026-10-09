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
all="$*"
sub=${1:-}; shift
jqexpr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) jqexpr=$2; shift 2 ;;
    *) shift ;;
  esac
done
# The merged half asks the same two subcommands a different question, so the
# fixture is chosen by the question rather than by the subcommand alone.
case "$all" in
  search*--merged*) fixture="$FIX/merged-search.json" ;;
  search*) fixture="$FIX/search.json" ;;
  pr*"--state merged"*) fixture="$FIX/merged-prs.json" ;;
  pr*) fixture="$FIX/prs.json" ;;
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

# Nothing merged recently, unless a case says otherwise. Every pass asks, so
# the cases about open PRs need an answer here too.
printf '[]' >"$FIX/merged-search.json"
printf '[]' >"$FIX/merged-prs.json"

# prs <mergeable> [isDraft] [headRefOid] [branch] [statusCheckRollup]
prs() {
  jq -n --arg m "${1:-CONFLICTING}" --argjson d "${2:-false}" \
    --arg oid "${3:-abc1234}" --arg br "${4:-feature/x}" \
    --argjson roll "${5:-[]}" '
    [{number:42, title:"a title", url:"https://github.com/acme/widget/pull/42",
      headRefName:$br, baseRefName:"trunk", headRefOid:$oid,
      mergeable:$m, isDraft:$d, statusCheckRollup:$roll}]' >"$FIX/prs.json"
}

# statusCheckRollup is a UNION and both arms are live on this account (measured:
# 1117 CheckRun entries against 2 StatusContext). A CheckRun carries
# status/conclusion/name; a StatusContext carries state/context and NO status
# field at all, so a naive `.status != "COMPLETED"` reads every commit status as
# forever-running. These builders keep that distinction in the fixtures.
check() { # check <name> <status> <conclusion>
  printf '{"__typename":"CheckRun","name":"%s","status":"%s","conclusion":"%s","workflowName":"wf"}' "$1" "$2" "$3"
}
ctx() { # ctx <context> <state>
  printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "$1" "$2"
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

echo "-- a conflicting draft is queued like any other PR --"
# Drafts were once excluded as "not yet news", which left a conflicting draft
# announced by NEITHER half: the CI half skips every CONFLICTING PR because the
# conflict is announced instead. On this account the PRs being actively worked
# in a live session are mostly drafts, so the exclusion hid exactly the case this
# program exists for -- and silently, with no log line.
# The rm is the Arrange, not tidiness: without it this case passes whenever the
# preceding group happened to leave a job, and stops testing anything the moment
# the groups are reordered.
/bin/rm -f "$JOB"
prs CONFLICTING true sha-d
run >/dev/null
eq 'a conflicting draft is queued' 'conflict' "$(job .kind)"
eq 'at its head' 'sha-d' "$(job .conflictHead)"

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
eq 'exactly one search for open PRs' '1' "$(grep '^search prs' "$TMP/gh.log" | grep -c -- '--state=open')"
eq 'exactly one open list, for the one repo' '1' "$(grep '^pr list' "$TMP/gh.log" | grep -c -- '--state open')"
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

CIJOB="$STATE/jobs/acme__widget__42__ci.json"
cijob() { jq -r "$1" "$CIJOB" 2>/dev/null; }

echo "-- a failing check queues a ci job, separate from the conflict one --"
STATE="$TMP/state-ci"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED FAILURE),$(check build COMPLETED SUCCESS)]"
out=$(run)
eq 'a ci job is written' 'yes' "$([ -f "$CIJOB" ] && echo yes || echo no)"
eq 'its kind says ci, not conflict' 'ci' "$(cijob .kind)"
eq 'it records the head it was seen at' 'head1' "$(cijob .ciHead)"
has 'it names the failing check' "$(cijob '[.pending[0].checks[]]|join(",")')" 'lint'
eq 'and not the passing one' 'false' "$(cijob '[.pending[0].checks[]]|index("build")!=null')"
# The conflict job is a different file on purpose: one PR can be both, and two
# detectors writing one file would each drop the other's pending.
eq 'no conflict job is written for a mergeable PR' 'no' \
  "$([ -f "$STATE/jobs/acme__widget__42__conflict.json" ] && echo yes || echo no)"

echo "-- checks still running are a THIRD answer, like UNKNOWN --"
# Announcing on the first red while others still run means announcing again for
# each one that lands after it. The pass says so on stdout rather than going
# quiet, and asks again next time.
STATE="$TMP/state-ci2"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED FAILURE),$(check build IN_PROGRESS '')]"
out=$(run)
eq 'nothing is queued while a check is still running' 'no' "$([ -f "$CIJOB" ] && echo yes || echo no)"
has 'and the pass says it is waiting' "$out" 'waiting'

echo "-- a StatusContext is not a forever-running check --"
# The union-type trap: a StatusContext has no .status, so `.status != COMPLETED`
# matches it and the detector waits forever on a PR whose checks all finished.
STATE="$TMP/state-ci3"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED FAILURE),$(ctx ci/legacy SUCCESS)]"
out=$(run)
eq 'a finished commit status does not stall the pass' 'yes' "$([ -f "$CIJOB" ] && echo yes || echo no)"

echo "-- a failing StatusContext counts as a failure --"
STATE="$TMP/state-ci4"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(ctx ci/legacy FAILURE)]"
run >/dev/null
has 'the commit status is named' "$(cijob '[.pending[0].checks[]]|join(",")')" 'ci/legacy'

echo "-- CANCELLED is not a failure --"
# Concurrency groups cancel the previous run on every push. Treating that as a
# failure would queue a job for the act of pushing twice.
STATE="$TMP/state-ci5"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED CANCELLED),$(check build COMPLETED SUCCESS)]"
run >/dev/null
eq 'a cancelled check queues nothing' 'no' "$([ -f "$CIJOB" ] && echo yes || echo no)"

echo "-- the same failure at the same head is not re-queued, a new head is --"
STATE="$TMP/state-ci6"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED FAILURE)]"
run >/dev/null
first=$(cijob .updatedAt)
out=$(run)
eq 'the second pass queues nothing' '' "$(printf '%s' "$out" | grep '^queue' || true)"
eq 'and leaves the job alone' "$first" "$(cijob .updatedAt)"
prs MERGEABLE false head2 feature/x "[$(check lint COMPLETED FAILURE)]"
out=$(run)
has 'a push that still fails is announced again' "$out" 'queue'
eq 'and the head moves with it' 'head2' "$(cijob .ciHead)"

echo "-- checks going green withdraws an undelivered job --"
prs MERGEABLE false head2 feature/x "[$(check lint COMPLETED SUCCESS)]"
run >/dev/null
eq 'the job is marked resolved' 'resolved' "$(cijob .status)"
eq 'and nothing is left owed' '0' "$(cijob '.pending|length')"
eq 'and the head is cleared so a later failure notifies afresh' 'null' "$(cijob .ciHead)"

echo "-- a draft IS queued for CI --"
# A red check on a draft is exactly what you want dealt with BEFORE marking it
# ready for review.
STATE="$TMP/state-ci7"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE true head1 feature/x "[$(check lint COMPLETED FAILURE)]"
run >/dev/null
eq 'a failing draft is queued' 'yes' "$([ -f "$CIJOB" ] && echo yes || echo no)"

echo "-- a conflicting PR is not also given a CI job --"
# The merge changes the tree the checks ran against, so fixing CI first is work
# done against a head that is about to be replaced. Conflict is announced; the
# new head re-evaluates CI on the next pass.
STATE="$TMP/state-ci8"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs CONFLICTING false head1 feature/x "[$(check lint COMPLETED FAILURE)]"
run >/dev/null
eq 'the conflict is queued' 'yes' \
  "$([ -f "$STATE/jobs/acme__widget__42__conflict.json" ] && echo yes || echo no)"
eq 'and the CI failure waits for it' 'no' "$([ -f "$CIJOB" ] && echo yes || echo no)"

echo "-- a PR whose mergeability is UNKNOWN gets no CI job yet, and waits as one PR --"
# UNKNOWN is the answer GitHub gives seconds before CONFLICTING, so treating it
# as "not conflicting" queues exactly the CI job the case above withholds, one
# pass early. It waits a pass instead, as the conflict half does, and the wait
# counts the PR once rather than once per half.
STATE="$TMP/state-ci8u"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs UNKNOWN false head1 feature/x "[$(check lint COMPLETED FAILURE)]"
out=$(run)
eq 'no CI job while mergeability is unknown' 'no' "$([ -f "$CIJOB" ] && echo yes || echo no)"
has 'the pass says it is waiting on the PR' "$out" 'waiting on 1 PR(s)'
prs UNKNOWN false head1 feature/x "[$(check lint COMPLETED FAILURE),$(check build IN_PROGRESS '')]"
out=$(run)
has 'unknown and still running is still one PR' "$out" 'waiting on 1 PR(s)'
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED FAILURE)]"
out=$(run)
has 'and the failure is queued once it turns out mergeable' "$out" 'queue acme/widget#42: checks failing'
eq 'at the head it was seen at' 'head1' "$(cijob .ciHead)"

echo "-- an UNKNOWN pass does not re-announce a failure at a new head either --"
# The likelier way to meet UNKNOWN: a push makes GitHub recompute mergeability,
# so the first pass after a red push asks while the answer is not in yet.
STATE="$TMP/state-ci8v"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED FAILURE)]"
run >/dev/null
prs UNKNOWN false head2 feature/x "[$(check lint COMPLETED FAILURE)]"
out=$(run)
eq 'a red push is not re-announced while mergeability is unknown' '' \
  "$(printf '%s' "$out" | grep '^queue' || true)"
eq 'and the job keeps the old head' 'head1' "$(cijob .ciHead)"
prs MERGEABLE false head2 feature/x "[$(check lint COMPLETED FAILURE)]"
out=$(run)
has 'it is re-announced once it turns out mergeable' "$out" 'queue acme/widget#42: checks failing'

echo "-- checks going green are withdrawn even while mergeability is unknown --"
# Only queueing waits for the answer. No answer to come would make a passing
# check worth delivering, and an undelivered red left in the queue for another
# pass is delivered to a session the moment one appears.
prs UNKNOWN false head2 feature/x "[$(check lint COMPLETED SUCCESS)]"
run >/dev/null
eq 'the job is resolved' 'resolved' "$(cijob .status)"
eq 'and nothing is left owed' '0' "$(cijob '.pending|length')"

echo "-- a PR with no checks at all is not a failure --"
STATE="$TMP/state-ci9"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[]"
run >/dev/null
eq 'no checks queues nothing' 'no' "$([ -f "$CIJOB" ] && echo yes || echo no)"

echo "-- a failing PR with no worktree is not queued --"
# There is no session to route to, so a job here would sit in the queue forever
# -- and unlike the conflict half this path says nothing on stdout, so the queue
# growing is the only symptom there would ever be.
STATE="$TMP/state-ci10"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 no/such/branch "[$(check lint COMPLETED FAILURE)]"
run >/dev/null
eq 'no worktree means no ci job' 'no' "$([ -f "$CIJOB" ] && echo yes || echo no)"

echo "-- --dry-run reports the failure and writes nothing --"
STATE="$TMP/state-ci11"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED FAILURE)]"
out=$(run --dry-run)
has 'the failure is still reported' "$out" 'checks failing'
eq 'but no job file is written' 'no' "$([ -f "$CIJOB" ] && echo yes || echo no)"

echo "-- the rollup rides the existing request, it is not a second one --"
# The entire reason this lives in pr-state-watch rather than in a detector of
# its own. A regression to a separate per-PR call would pass every behavioural
# assertion above while multiplying the request count -- against the search
# API's own 30/min limit -- so the shape is asserted, not just the outcome.
STATE="$TMP/state-ci12"
CIJOB="$STATE/jobs/acme__widget__42__ci.json"
prs MERGEABLE false head1 feature/x "[$(check lint COMPLETED FAILURE)]"
run >/dev/null
eq 'exactly one open pr list call for the repo' '1' "$(grep '^pr list' "$TMP/gh.log" | grep -c -- '--state open')"
has 'and it asks for the rollup inline' "$(grep '^pr list' "$TMP/gh.log")" 'statusCheckRollup'
eq 'no checks/run subcommand is called at all' '0' \
  "$(grep -cE '^(run|checks|api) ' "$TMP/gh.log" || true)"

# --- merged ------------------------------------------------------------------
# A merged PR drops out of the open search, so it is found by a search of its
# own. The session on the branch is told so it can say what it is leaving
# undone and whether ending it would lose anything. No open PRs in these cases:
# the merged half must run even when nothing is open, which is the ordinary
# state right after your last PR merges.
#
# EVERY case below arranges its own fixtures through arrange_merged. Several of
# them assert only that nothing happened, and such a case inheriting its
# fixtures passes vacuously the moment the case it inherited from changes.

# merged <number>... -- the search result: these PRs merged recently.
merged() {
  local n out=""
  for n in "$@"; do
    out="$out${out:+,}{\"number\":$n,\"repository\":{\"name\":\"widget\",\"nameWithOwner\":\"acme/widget\"}}"
  done
  printf '[%s]' "$out" >"$FIX/merged-search.json"
}
# merged_prs <head> [branch] -- the repo's merged list. It returns 43 as well,
# because `gh pr list` answers for the whole repo; only the search says which
# ones are new, and a filter that quietly matches everything is this
# pipeline's signature bug.
merged_prs() {
  jq -n --arg oid "${1:-m1}" --arg br "${2:-feature/x}" '
    [{number:42, title:"a title", url:"https://github.com/acme/widget/pull/42",
      headRefName:$br, headRefOid:$oid},
     {number:43, title:"older", url:"https://github.com/acme/widget/pull/43",
      headRefName:$br, headRefOid:"old43"}]' >"$FIX/merged-prs.json"
}
with_session() {
  printf '[{"pid":1,"cwd":"%s","kind":"interactive","sessionId":"sess-1","startedAt":1,"status":"idle"}]' \
    "$WT" >"$FIX/agents.json"
}
without_session() { printf '[]' >"$FIX/agents.json"; }
# arrange_merged <state-name> [branch] -- a fresh queue, #42 merged on
# <branch> (default: the one checked out in $WT), a live session in $WT.
arrange_merged() {
  STATE="$TMP/$1"
  merged 42
  merged_prs m1 "${2:-feature/x}"
  with_session
  printf '%s' "$REPO" >"$FIX/ghq-github.com_acme_widget"
  printf '[]' >"$FIX/search.json"
  printf '[]' >"$FIX/prs.json"
}
MJOB() { printf '%s' "$STATE/jobs/acme__widget__42__merged.json"; }
mjob() { jq -r "$1" "$(MJOB)" 2>/dev/null; }
exists() { [ -f "$1" ] && echo yes || echo no; }

echo "-- a merged PR is queued for the session on that branch --"
arrange_merged state-m1
out=$(run)
eq 'a merged job is written' 'yes' "$(exists "$(MJOB)")"
eq 'its kind says merged' 'merged' "$(mjob .kind)"
# The session compares its own HEAD against this to tell whether anything local
# is missing from what merged. Without it "is it safe to end" has no answer.
eq 'it records the head that merged' 'm1' "$(mjob .mergedHead)"
eq 'the worktree is resolved' "$WT" "$(mjob .worktree)"
eq 'the session is resolved' 'sess-1' "$(mjob .sessionId)"
eq 'exactly one pending item' '1' "$(mjob '.pending|length')"
has 'the run says what merged' "$out" 'queue acme/widget#42: feature/x was merged'
has 'and counts it' "$out" 'queued 1 merge(s)'
eq 'a PR the search did not name is left alone' 'no' \
  "$(exists "$STATE/jobs/acme__widget__43__merged.json")"

echo "-- a merge is announced once, delivered or not --"
# A merge happens once, so unlike a conflict there is no head to re-key on: the
# job existing IS the record. The search keeps returning the PR for the whole
# lookback, so anything weaker re-announces it every five minutes.
arrange_merged state-m2
run >/dev/null
eq 'the first pass queues it' '1' "$(mjob '.pending|length')"
jq '.pending = [] | .status = "delivered"' "$(MJOB)" >"$TMP/m.json" && mv "$TMP/m.json" "$(MJOB)"
out=$(run)
eq 'the next pass queues nothing' '' "$(printf '%s' "$out" | grep '^queue' || true)"
eq 'and does not re-arm the delivered job' '0' "$(mjob '.pending|length')"

echo "-- merging withdraws the PR's conflict and ci jobs, even with the worktree gone --"
# They are about a head that can no longer change. The case that matters is the
# one arranged here: the worktree already removed, so nobody is told about the
# merge -- and the dispatcher would hold these for good, since nothing expires a
# job. Withdrawing only when there is a session to tell would miss exactly that.
arrange_merged state-m3 no/such/branch
mkdir -p "$STATE/jobs"
jq -n '{kind:"conflict", pending:[{id:"conflict:m1", kind:"conflict"}], status:"pending", conflictHead:"m1"}' \
  >"$STATE/jobs/acme__widget__42__conflict.json"
jq -n '{kind:"ci", pending:[{id:"ci:m1", kind:"ci", checks:["lint"]}], status:"pending", ciHead:"m1"}' \
  >"$STATE/jobs/acme__widget__42__ci.json"
# The review job has no kind and no suffix. A human's feedback on a merged PR is
# for a human to dispose of, and the queue is its only copy -- a glob like
# `${prefix}*.json` would take it along with the two above.
jq -n '{pending:[{id:"review:1", kind:"review", author:"bob", body:"nit"}], status:"pending"}' \
  >"$STATE/jobs/acme__widget__42.json"
run >/dev/null
eq 'the conflict job is emptied' '0' "$(jq '.pending|length' "$STATE/jobs/acme__widget__42__conflict.json")"
eq 'the ci job is emptied' '0' "$(jq '.pending|length' "$STATE/jobs/acme__widget__42__ci.json")"
eq 'and says why' 'merged' "$(jq -r .status "$STATE/jobs/acme__widget__42__ci.json")"
eq 'the review job keeps its feedback' '1' "$(jq '.pending|length' "$STATE/jobs/acme__widget__42.json")"
eq 'and no merged job is written without a worktree' 'no' "$(exists "$(MJOB)")"

echo "-- no live session means nobody to tell, and no job --"
# Queued anyway, it would be held on every dispatch pass for as long as the
# worktree stays -- which is exactly the forgotten worktree this is about.
arrange_merged state-m4
without_session
out=$(run)
eq 'no job is written' 'no' "$(exists "$(MJOB)")"
eq 'and nothing is said about it' '' "$(printf '%s' "$out" | grep -v '^$' || true)"
# ...but it is not forgotten either: the search still returns the PR, so a
# session opened later in that worktree is told on the next pass.
with_session
out=$(run)
has 'a session started later is told' "$out" 'queue acme/widget#42: feature/x was merged'

echo "-- a merged branch with no worktree is already cleaned up --"
arrange_merged state-m5 no/such/branch
out=$(run)
eq 'no job is written' 'no' "$(exists "$(MJOB)")"
eq 'and nothing is said about it' '' "$(printf '%s' "$out" | grep -v '^$' || true)"

echo "-- a merged PR in a repo with no local checkout is not this pipeline's business --"
arrange_merged state-m6
/bin/rm -f "$FIX/ghq-github.com_acme_widget"
out=$(run)
eq 'no job is written' 'no' "$(exists "$(MJOB)")"
eq 'and no merged list is spent on it' '0' "$(grep '^pr list' "$TMP/gh.log" | grep -c -- '--state merged' || true)"

echo "-- the merged half costs one search, and a list only where it found one --"
arrange_merged state-m7
run >/dev/null
eq 'exactly one merged search' '1' "$(grep '^search prs' "$TMP/gh.log" | grep -c -- '--merged')"
eq 'one merged list for the one repo' '1' "$(grep '^pr list' "$TMP/gh.log" | grep -c -- '--state merged')"
merged
run >/dev/null
eq 'nothing merged means no list at all' '0' "$(grep '^pr list' "$TMP/gh.log" | grep -c -- '--state merged' || true)"

echo "-- both merged requests are bounded by the merge date --"
# The search is the obvious one. The LIST is the one that bites: `gh pr list`
# orders by creation, not by merge (checked on a live repo -- a PR merged ten
# minutes after its neighbour was listed after it), so under a bare --limit a
# long-lived PR that merged today falls off the end in a busy repo and is never
# announced. Bounding it by merge date makes the limit irrelevant.
#
# PR_STATE_WATCH_MERGED_DAYS has to reach both. A lookback of 0 days is today,
# which the test can compute without the BSD/GNU date split.
arrange_merged state-m8
before=$(date -u +%Y-%m-%d)
PR_STATE_WATCH_MERGED_DAYS=0 run >/dev/null
after=$(date -u +%Y-%m-%d)
for req in 'search prs' 'pr list'; do
  line=$(grep "^$req" "$TMP/gh.log" | grep -- 'merged' | head -1)
  case "$line" in
    *"merged:>=$before"* | *"merged:>=$after"*) ok "the $req is bounded by today when the lookback is 0 days" ;;
    *) no "the $req is bounded by today when the lookback is 0 days" "[$line]" ;;
  esac
done
# The default is a real date, not an empty qualifier that GitHub would read as
# no bound at all.
run >/dev/null
eq 'the default bound is a date' '1' \
  "$(grep -- '--merged' "$TMP/gh.log" | grep -cE 'merged:>=[0-9]{4}-[0-9]{2}-[0-9]{2}')"

echo "-- a merged search or list that fails is reported, not read as nothing merged --"
# The same rule as the open half's "could not list pull requests": an empty
# answer from a failed request is indistinguishable from a quiet week.
arrange_merged state-m9
/bin/rm -f "$FIX/merged-search.json"
out=$(run)
has 'a failed search says so' "$out" 'could not search for merged pull requests'
arrange_merged state-m9
: >"$FIX/merged-prs.json"
out=$(run)
has 'a failed list names the repository' "$out" 'skip acme/widget: could not list merged pull requests'
eq 'and writes nothing' 'no' "$(exists "$(MJOB)")"

echo "-- --pr finds a merged PR without any search --"
arrange_merged state-m10
out=$(run --pr acme/widget#42)
eq 'it queues' 'merged' "$(mjob .kind)"
eq 'and spends no search request' '0' "$(grep -c '^search prs' "$TMP/gh.log")"
eq 'and leaves the other merged PR alone' 'no' \
  "$(exists "$STATE/jobs/acme__widget__43__merged.json")"

echo "-- --dry-run reports the merge and writes nothing --"
arrange_merged state-m11
mkdir -p "$STATE/jobs"
jq -n '{kind:"ci", pending:[{id:"ci:m1", kind:"ci", checks:["lint"]}], status:"pending", ciHead:"m1"}' \
  >"$STATE/jobs/acme__widget__42__ci.json"
out=$(run --dry-run)
has 'the merge is still reported' "$out" 'was merged'
eq 'but no job file is written' 'no' "$(exists "$(MJOB)")"
eq 'and nothing is withdrawn' '1' "$(jq '.pending|length' "$STATE/jobs/acme__widget__42__ci.json")"

echo "-- an open search that fails is reported, not read as no open PRs --"
# The open half's whole input. Read as "nothing open", a failed request turns
# every conflict and red check silent until it happens to succeed again -- the
# same rule the merged half follows, in the direction that matters more.
STATE="$TMP/state-o1"
prs CONFLICTING
/bin/cp "$FIX/search.json" "$TMP/search.json.keep"
/bin/rm -f "$FIX/search.json"
out=$(run)
has 'a failed open search says so' "$out" 'could not search for open pull requests'
eq 'and queues nothing from it' 'no' \
  "$([ -f "$STATE/jobs/acme__widget__42__conflict.json" ] && echo yes || echo no)"
# An answer of [] is a real "nothing open", the state right after the last PR
# merges, and must stay quiet.
printf '[]' >"$FIX/search.json"
out=$(run)
eq 'an empty but successful search is not reported as a failure' 'no' \
  "$(printf '%s' "$out" | grep -q 'could not search for open' && echo yes || echo no)"
/bin/cp "$TMP/search.json.keep" "$FIX/search.json"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
