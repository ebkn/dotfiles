# pr-review-watch — stage 1 of the PR review pipeline

When a review lands on a PR, route it to the Claude Code session that is working
on that branch.

The pipeline is split into **detect-and-queue** (this script) and **deliver**
([pr-review-dispatch](pr-review-dispatch.md)), and the split is the design, not a
phasing convenience. "A review arrived" and "this session may be interrupted
right now" are unrelated facts, and a session that is mid-turn must not be typed
into; folding delivery into the poller would make that unenforceable, so a job
sitting in the queue *is* the representation of "a review arrived while you were
busy".

**The queue is the mechanism that makes interruption avoidable, so it must never
be bypassed.**

The pid-based lock and the worktree/session lookup both programs share live in
[pr-review-common.md](pr-review-common.md).

## Polling is free while idle, because of the conditional request

GitHub documents both halves — "there is an `X-Poll-Interval` header that
specifies how often (in seconds) you are allowed to poll" and "if there are no
new notifications, you will see a `304 Not Modified` response, **leaving your
current rate limit untouched**".

So the stored `Last-Modified` is not an optimisation, it is what keeps a 60s poll
off the 5000/hr budget entirely.

**`gh api -i` exits non-zero on that 304** (verified), so the status must be read
from the status line; trusting the exit code turns every quiet poll into an
error.

The stored value is advanced only after the whole batch is queued, since a crash
mid-batch would otherwise be hidden by the next poll's 304.

## `all=true` is deliberate

Without it the API returns only *unread* notifications, which would make
GitHub's read state load-bearing — opening the PR in a browser would silently
drop the job. Idempotence comes from the job's own `seen` id set instead.

## The session lookup

`claude agents --json` is Claude Code's own registry of live sessions
(`--help`: "for scripting; does not require a TTY"), reporting `cwd`,
`sessionId` and a `status` of `idle`/`busy`/`waiting` (plus `waitingFor`).

PR → branch → worktree → `cwd` needs no registry of its own:
`git worktree list --porcelain` and that JSON are enough.

**Do not reach for `claude --resume <id> --bg` as the delivery mechanism while a
TUI session is open.** `--help` is explicit that it "starts a copy and says so
when the session is already running" — so on the normal setup here (unfinished
work left open in a tab) it forks the conversation and puts a second writer on
the same worktree, rather than continuing the session. It is the fallback for a
PR whose session has exited, not the default path.

## The two exclusions are behavioural, not cosmetic

- **`ci_activity` is not a review reason.** A red check would otherwise wake a
  session per flake.
- **Comments authored by the token's own login are dropped.** That is what stops
  a reply this pipeline posts from re-triggering it.
- `subscribed` is excluded alongside `ci_activity` because it fires for activity
  on any PR you merely watch, which is far wider than the PRs this can act on.

**`REASONS` is hand-copied from GitHub's documented `reason` vocabulary and
therefore rots silently, in the one direction that hurts** — a value renamed
upstream stops matching, the PR is never queued, and nothing reports an error.
The full documented set is listed above it so the two stay diffable, the same
discipline `zsh/ssh-parse-argv.test.zsh` applies to ssh(1)'s option class.

## State

State lives in `${XDG_STATE_HOME:-~/.local/state}/pr-review-watch` — **state, not
cache**: losing the `seen` high-water means re-queueing feedback that was already
handled.

`seen` is the watcher's high-water and delivery deliberately never touches it;
clearing it re-queues everything on the next poll.

## launchd

The poll is driven by `launchd/com.ebkn.pr-review-watch.plist` at the 60s
`X-Poll-Interval` GitHub asks for. The plist header carries the two traps:

- a launchd agent inherits **none** of the login shell's environment, so `PATH`
  must be spelled out or every `command -v` fails and polling silently never
  happens;
- it must be `sh -c`, never `sh -lc`, because a login shell runs path_helper and
  rebuilds `PATH` from `/etc/paths`, dropping `/opt/homebrew/bin` and undoing the
  `EnvironmentVariables` entry.

`link_dotfiles()` links the plist and the `~/.local/bin` script as a pair — the
plist execs through that symlink, so linking one without the other leaves launchd
calling a path that does not exist.

**Linking is not loading**, and the gap is invisible — see
[launchd-load.md](launchd-load.md).

## `--pr owner/repo#N`

**GitHub never notifies you about your own comments**, which is why this exists.
Verified on ebkn/dotfiles#30: a review with inline comments plus a conversation
comment, all posted by the token owner, produced **no** notification at all —
only a `ci_activity` CheckSuite entry for the failing workflow. So a solo
end-to-end on your own PR has no trigger to fire, and the notification path
cannot be exercised without a second account.

`--pr` bypasses the poll entirely (it does not even send the conditional request,
and never advances the stored `Last-Modified`) and uses the epoch as its
first-sight cutoff rather than the notification timestamp — asking for a PR by
name means asking for the feedback that is on it, so seeding history as `seen`
the way the notification path does would queue nothing.

It doubles as the way to adopt a PR whose review predates this tool. The
own-comment filter still applies, so a real test needs the state dir's `login`
cache seeded with some other name.

## No desktop notification, and no expiry

`terminal-notifier` was dropped, so the queue and the session prompt are the only
surfaces.

**A job has no expiry** — no age cutoff anywhere — so a session busy for ten
minutes simply holds on every pass and receives everything owed on the first pass
after it goes idle; `pending` accumulates meanwhile, so a burst arrives as one
prompt.

## Testing (`pr-review-watch.test.sh`)

Stubs only the network-facing commands (`gh`, `ghq`, `claude`) and uses a
**real** git repository with a real worktree, because `worktree_for_branch`'s
contract is what git actually reports.

**The load-bearing decision is that the `gh` stub applies the `--jq` expression
it is handed** rather than returning a pre-shaped answer. Every filter in this
script is a jq one-liner, and jq's rebinding of `.` inside a pipe makes them
wrong in ways that produce an empty result instead of an error:
`select($reasons | index(.reason))` reads `.reason` against the *array*, matches
nothing, and makes a working poller queue silently nothing. Found only by running
the real expression against real GitHub-shaped fixtures, and it is now the first
case that goes red if reintroduced.

**Assert on the queued job files, never on the exit status**: a quiet poll and a
broken filter both print nothing and exit 0.

The cases that earn their keep encode pipeline rules rather than parsing:

- **History is seeded on first sight.** Adopting a week-old PR must not dump a
  week of comments into one prompt, so anything older than the notification's own
  timestamp lands in `seen`, while the review that triggered the run still lands
  in `pending`.
- **`pending` accumulates and never replaces.** That is the whole representation
  of "a review arrived while the session was busy", so a second poll must leave
  the first review still owed.
- **Own comments are dropped.** Otherwise a reply this pipeline posts
  re-triggers it — an infinite loop whose only symptom is a session that keeps
  waking.
- **`ci_activity` writes no job.** A red check is not review feedback.
- A `PENDING` review — `submitted_at: null`, a draft only its author can see —
  must not be queued as though it had been posted.

**Nested worktrees get their own end-to-end cases**: a PR on the outer checkout
with a session only in an inner worktree must resolve to no session at all, and
one deeper than a worktree root must still count as inside it. That is the shape
`gw` produces on every machine here.

The `mktemp -d` path is resolved with `pwd -P` for the reason
`git-worktree.test.zsh` documents — macOS says `/var/…`, git says
`/private/var/…`, and every path comparison silently compares the wrong prefix
without it.

Written for bash 3.2 (`/bin/bash` on macOS): no `mapfile`, no associative
arrays.
