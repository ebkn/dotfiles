# pr-review-common.sh

The pid-based lock and the repository/worktree/session lookups shared by the
three programs on this pipeline: [pr-review-watch](pr-review-watch.md),
[pr-state-watch](pr-state-watch.md) and
[pr-review-dispatch](pr-review-dispatch.md).

`repo_path` and `worktree_for_branch` live here rather than in either detector
because both have to answer the same two questions -- is there a local checkout,
and is the branch checked out anywhere -- before they can route anything at all.
`repo_path` takes its extra-repos list as an argument rather than reading a
caller global, so the fragment carries no assumption about who sourced it.

Sourced through `$(dirname "$(readlink -f "$0")")` so it resolves next to the
real script rather than next to the `~/.local/bin` symlink (the idiom `read-doc`
uses for its stylesheet). It carries no shebang, so it is named explicitly in
`bin/lint-shell` and declares `# shellcheck shell=bash`.

## The lock is pid-based, not time-based

That is the whole point of it existing as a file. The first version stole any
lock older than ten minutes, which silently assumed no run legitimately takes
that long — an assumption nothing enforced and nothing checked, and one that gets
worse as the queue grows.

It now writes the holder's pid into the directory and steals only when `kill -0`
says that pid is gone, so there is no timeout to tune.

The age check survives **only** as the fallback for a lock with no readable pid,
which is a real state and not a theoretical one: `mkdir` can succeed while the
pid write fails on a full or read-only volume, and a lock left by an older version
has no pid file at all. That fallback is an hour rather than ten minutes precisely
because it is now guesswork and should almost never be what frees a lock.

`release_lock` refuses to act unless the pid file names the calling process, so a
run that skipped because somebody else held the lock cannot free it on the way
out — without that check an EXIT trap would hand the lock away on every contended
run.

**Both failure directions are silent and neither is recoverable by retrying:**
refusing to steal a dead holder's lock stops the pipeline **forever** (both
programs exit 0 when they cannot take it, so there is no output anywhere), and
stealing a live holder's lets two runs interleave writes to one job file.

`bin/tmux-track-session` deliberately does *not* settle for `kill -0`: a recycled
pid there is destructive, where here it only costs a missed steal.

## Which session owns a worktree: LONGEST prefix, never containment

Containment is the obvious answer and it is wrong here, because `gw` nests every
worktree under `<checkout>/git-worktrees/`, making the main checkout a string
prefix of all of them: a PR built from the main checkout matched every session
beneath it and, taking the newest, delivered a review to an unrelated branch.

Measured on this machine before the fix — worktree `~/dotfiles` matched four
sessions and picked the one on `fix/tmux-change-session`.

So the caller passes every worktree from `git worktree list` and a session counts
only when the worktree owning its cwd is the one being asked about. Using git's
list rather than the directory tree also means a plain directory sitting where a
worktree would sit is not mistaken for one.

Two things bite when editing it:

1. **The paths are compared as strings, so they must arrive exactly as git
   reports them.** macOS git says `/private/var` where the shell says `/var`, and
   mixing the two matches nothing.
2. **`$cwd | startswith(. + "/")` is a trap.** The pipe rebinds `.` to `$cwd`
   inside the argument, so the element is unreachable, the test silently becomes
   `$cwd` against itself, and every nested cwd resolves to null — the same jq
   rebinding that made `select($reasons | index(.reason))` queue nothing. Bind the
   element with `as $w` and compare against that.

Both halves passed the shallow cases while broken, which is why the suite carries
a cwd *deeper* than a worktree root.
