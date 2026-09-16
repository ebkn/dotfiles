# pr-state-watch — the second detector on the review pipeline

Two things go wrong on a PR of yours that nothing tells you about: it stops
merging, and its checks go red. This notices both and hands the branch's Claude
Code session an instruction to deal with it.

Both are **polled state**, not received events, which is what makes them one
program rather than two. The decisive detail is that `statusCheckRollup` comes
back in the `gh pr list` request that already fetches `mergeable`, so the second
question costs **no extra request**; a separate detector would have duplicated
the `gh search prs` call against the search API's own 30/min limit. The name
changed from `pr-conflict-watch` when the second question arrived.

It feeds the **same queue** and the **same deliverer**
([pr-review-dispatch](pr-review-dispatch.md)) as
[pr-review-watch](pr-review-watch.md). A conflict and a review are the same shape
of event — something happened on your PR that the session on that branch has to
act on — so the socket, the liveness rules, the lock discipline and the "a job in
the queue means it arrived while you were busy" semantics are all reused
unchanged. Only the detection and the prompt differ.

## Why it is a separate program

**A conflict raises no notification.** GitHub notifies about reviews, comments,
mentions and checks. It says nothing when somebody else's merge to `main` makes
your branch unmergeable — there is no `reason` in the notification vocabulary for
it, because nothing happened *to your PR*; something happened to a different
branch.

So this cannot ride the notifications endpoint, and that matters more than it
sounds. The review path's cost argument rests entirely on the conditional
request: a quiet minute returns `304` and leaves the rate limit untouched, which
is what makes a 60-second poll free. Conflict is a **state to be polled**, not an
event to be received, so there is nothing to make conditional. Folding it into
`pr-review-watch` would have put an unconditional request on every tick of a path
whose whole design is that a quiet tick costs nothing.

It is also why the two have different intervals: 60s there, 300s here.

## The cost is controlled by shape, not by frequency

One `gh search prs --author=@me --state=open` returns **every open PR you have,
anywhere, in a single request**. One `gh pr list --json mergeable,…` per repo
that has one returns mergeability for all of that repo's PRs at once.

Typically two or three requests per pass, whatever the PR count. The obvious
alternative — walk `ghq list` (77 repos on this machine) and ask each — is 77
requests for the same answer, and still misses a checkout outside ghq.

The search API has its own much tighter limit (**30 requests/minute**, separate
from the 5000/hr core budget), which is the other reason for the 5-minute
interval. `bin/pr-state-watch.test.sh` pins the request shape for exactly this
reason: a regression to per-PR requests would pass every behavioural assertion
while quietly multiplying the cost.

## `UNKNOWN` is a third answer, and getting that wrong is silent both ways

GitHub computes mergeability **lazily**. The first query returns `UNKNOWN` and
starts a background job; a query seconds later returns the real value. Verified
on a live PR here — `UNKNOWN`, then `CONFLICTING`, from two calls moments apart.

So `mergeable` has three values and both collapses are silent failures:

- reading `UNKNOWN` as "fine" makes the detector **go silent**, and an empty
  queue looks exactly like a week with no conflicts;
- reading it as "conflicting" makes it **cry wolf**, which trains its reader to
  ignore it — the same outcome, reached differently.

It is therefore neither. The pass counts it, says so on stdout rather than
staying quiet, and asks again next time — by which point GitHub has computed the
answer this pass just asked for.

## The idempotence key is the head oid, not a `seen` set

The review path keys on item ids: every comment is an event with an identity, and
`seen` is a high-water mark over them.

**A conflict has no id.** It is a state that persists across every poll until
somebody fixes it, so a per-item set cannot represent it and re-announcing it
every five minutes is how a notifier gets muted.

The job therefore stores `conflictHead`, the head oid the conflict was seen at:

- **same head, still conflicting** → say nothing. Already reported.
- **new head, still conflicting** → announce again. The session pushed and the
  branch *still* does not merge, which is precisely when it needs telling twice.
- **mergeable again** → clear `conflictHead` and empty `pending`. Clearing it is
  what lets a *later* conflict at the same oid — the base moved, the branch never
  did — be announced instead of mistaken for the one already handled.

Emptying `pending` on the way through also means **a conflict that resolves
itself before delivery is never delivered**: somebody else's merge undid it, and
the session should not be interrupted for it.

`pending` holds exactly one item and **replaces** rather than accumulating, the
opposite of the review path. Two conflicts on one PR are not two things to
address; the older one describes a head that no longer exists.

## Failing checks

The same shape as the conflict half — polled state, keyed on the head oid — with
four decisions of its own.

**`statusCheckRollup` is a union, and both arms are live.** Measured on this
account: 1117 `CheckRun` entries against 2 `StatusContext`. A `CheckRun` carries
`status`/`conclusion`/`name`; a `StatusContext` carries `state`/`context` and
**no `status` field at all**. So the obvious `.status != "COMPLETED"` reads every
commit status as forever-running and the detector waits for a check that finished
long ago. The jq branches on `__typename`, and the fixtures carry both arms.

**Checks still running are a third answer**, exactly as `UNKNOWN` is for
mergeability. Announcing on the first red while others are still running means
announcing again for each one that lands after it, so a pass with anything
in-flight counts itself as waiting and asks again in five minutes.

**`CANCELLED` is not a failure.** Concurrency groups cancel the previous run on
every push, so counting it would queue a job for the act of pushing twice.
`FAILURE`, `TIMED_OUT` and `STARTUP_FAILURE` are the failures;
`SKIPPED`/`NEUTRAL`/`SUCCESS` are not.

**A `CONFLICTING` PR gets no CI job.** The merge is about to replace the tree the
checks ran against, so fixing them first is work against a head that will not
survive. The conflict is announced, and the next pass re-evaluates CI on the new
head.

### Drafts are included here, and excluded from conflicts

The only asymmetry between the two halves, and it is deliberate. A conflict on a
draft is not yet news — the branch is still being written. A red check on a draft
is exactly what should be dealt with **before** marking it ready for review.

### Flakes are the session's call, not this program's

The review path excludes `ci_activity` from its notification reasons with the
reason "a red check would otherwise wake a session per flake", and that objection
does not disappear because the feature was asked for. What answers it is the
idempotence key plus where the judgement sits.

Keying on the head oid means a session is woken **at most once per push**: a
flake that stays red does not re-announce, and a push that does not fix it
announces again, which is when it needs saying twice.

Whether a failure *is* a flake needs the log, which this program has not read.
Re-running a check would also mean a cron job writing to GitHub, which is the
line this pipeline does not cross anywhere else. So the prompt names the
possibility and tells the session to re-run rather than invent a fix — the
judgement goes to the only party that can see the output.

**The prompt's other prohibition is the load-bearing one.** The cheapest way to
make a red check green is to weaken what it checks, and a session told only "make
CI pass" has every incentive to reach for it. See
[pr-review-dispatch.md](pr-review-dispatch.md) for why that text is where it is.

## Job files are separate, and so is the lock

`<repo>__<pr>__conflict.json` and `<repo>__<pr>__ci.json`, beside the review
path's `<repo>__<pr>.json`. Two writers on one file would interleave, and each
would drop the other's `pending` on its next pass — which applies to the two
halves of this program as much as to the two programs, since one PR can be both
conflicted and failing.

For the same reason the lock is `.state-lock`, not the watcher's `.lock`.
They have no reason to exclude each other, and sharing one would mean a review
poll that is slow — or wedged behind a dead holder — silently cancels every
conflict pass for as long as it holds.

## What it does NOT do

**It never fetches, never merges, never writes to a worktree.** Neither does the
dispatcher. The session does the merge, in a turn a human can see.

That was a decision, not an omission. Having the cron job run `git merge` itself
was considered and rejected: this fires unannounced, and a launchd agent starting
a merge in a worktree you are mid-edit in either fails on the dirty tree or
entangles your uncommitted work with conflict markers — and it does so at a
moment you did not choose. The instruction to check `git status --short` and
**stop** if it is not clean is the first line of the prompt for the same reason.

The consequence is the same as the review path's: a PR with no live session on
its branch is detected and queued but not delivered, and waits. `--author @me`
and the local-worktree requirement mean it only ever speaks about branches this
machine is actually working on.

## The prompt is an instruction, not a relay

A conflict carries no prose from anybody — GitHub only ever said `CONFLICTING` —
so unlike a review, the prompt file is **written here**. That makes it the one
piece of text in this pipeline that can be wrong with no upstream to blame, which
is why `pr-review-dispatch.test.sh` asserts on its content.

It names commands rather than describing a goal, because two of the choices are
not the session's to make:

- **Merge, never rebase.** Inline review comments are anchored to commits, so a
  rebase plus force-push detaches every one of them — on exactly the PRs this
  pipeline exists to serve. No force-push is needed or wanted; the merge pushes
  as a fast-forward.
- **The base branch comes from the job**, not from a hardcoded `main`. A repo
  whose default branch is anything else would otherwise be told to fetch a ref
  that does not exist, and a failing `git fetch` is the kind of error a session
  works around instead of reporting.

The first line of the socket message leads with `[pr-state-watch]`, because
the receiving terminal previews only that line until a human expands it: sharing
the review prefix would make a conflict read as a review comment in the only text
most deliveries are ever judged by.

## Running it by hand

```sh
pr-state-watch --dry-run             # report, write nothing
pr-state-watch --pr owner/repo#42    # one PR, skipping the search entirely
pr-review-watch --print                 # the whole queue, conflict jobs included
```

The queue is shared, so `--print` lives on the other program rather than being
duplicated here.

## launchd

`launchd/com.ebkn.pr-state-watch.plist`, at 300s. The plist carries the same
two traps the review one does — `PATH` spelled out because a launchd agent
inherits none of the login shell's environment, and `sh -c` never `sh -lc`
because a login shell's path_helper rebuilds `PATH` and drops
`/opt/homebrew/bin`.

**Linking is not loading**, and the gap is invisible — see
[launchd-load.md](launchd-load.md).

## Testing (`pr-state-watch.test.sh`)

Stubs only the network-facing commands (`gh`, `ghq`, `claude`); git and the
worktrees are real, because `worktree_for_branch`'s contract is what git actually
reports.

The `gh` stub **applies the `--jq` expression it is handed** rather than
returning a pre-shaped answer, for the reason the watcher's suite documents: jq
rebinds `.` inside a pipe, and every filter this pipeline has got wrong that way
produced an *empty result* instead of an error. It also logs every call, so the
request shape above is assertable.

The cases that earn their keep are the state machine, not the parsing:

- the same conflict is **not** re-queued on the next pass, and a new head **is**;
- `UNKNOWN` neither clears a real conflict nor invents one;
- becoming mergeable withdraws an undelivered job;
- `--pr` on a repo with two conflicting PRs touches only the one asked for — a
  filter that quietly matches everything is this pipeline's signature bug;
- the watcher's lock does not block a conflict pass, asserted on the outcome
  rather than on the filename, so it would still fail if the program simply
  stopped locking.

Written for bash 3.2 (`/bin/bash` on macOS): no `mapfile`, no associative arrays.
