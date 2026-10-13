# zsh/git.zsh — the git worktree flow

`gw <branch>` creates a branch and worktree and changes into it; `gdmerged`
deletes merged branches and removes their worktrees. Also holds the git aliases,
`gs`, and the ghq picker.

## git-worktree.test.zsh

Covers `gw()` and `gdmerged()`, **the two destructive functions here** —
`gdmerged` deletes branches and removes worktrees, `gw` checks out other people's
PRs.

Every case builds a **real** git repository in a temp dir and asserts on what git
ends up holding (which branches exist, which worktrees are registered). Only `gh`
and `fzf` are stubbed, **never git**, because a stubbed git would keep passing if
git changed what these commands mean.

Five things are worth knowing before editing it:

1. **The `mktemp -d` path must be resolved with `:A`** — macOS hands back
   `/var/…`, git reports `/private/var/…`, and without that every path comparison
   is against the wrong prefix *and* `gw`'s "changing directory to repository
   root" branch fires on every call.
2. **The `fzf` stub honours `--accept-nth`, and searches only the `--nth`
   columns**, because `gw` depends on both: the menu carries the absolute path in
   a hidden third column, and a stub returning the whole line hands `cd` three
   tab-separated fields. Searching that hidden column too, as a plain `grep` of
   the line does, made a wrong hidden path fail for the wrong reason, and a pick
   fail whenever the temp dir's path contained the word picked. The stub counts
   `--nth` among the `--with-nth` columns, as fzf does, and reads
   `FZF_DEFAULT_OPTS` before the arguments, so one case runs under the value
   `.zshenv` exports: its `--nth=-1` would leave only the path searchable, and
   `gw`'s own `--nth=1,2` is what overrides it. Everywhere else the suite unsets
   `FZF_DEFAULT_OPTS`, since `zsh <file>` reads `~/.zshenv` and CI has none.
3. **The y/N prompt reads `/dev/tty` directly** — deliberately, since the branch
   list already occupies stdin — so **no redirection can answer it**.
   `_gdmerged_confirm` exists purely as the seam a test can override, and both
   answers are exercised through it.
4. **`run` reports the exit status as well as the final `PWD`**, because agents
   run `gw` and act on its status — a failure returning 0 would leave them working
   in the main checkout. "No `gh`" is a `PATH` holding only a symlink to git,
   since on the CI runner a real `gh` shares `/usr/bin` with git. The picker is
   the same: the `fzf` stub exits as fzf does (130 for ESC, 1 for no match, 2
   for an error), and only the first two may come back from `gw` as 0.
5. **A case whose assertion is an absence needs a control.** The hook case first
   shows its fixture `post-checkout` hook firing on a plain `git worktree add`;
   without that, a hook that never ran would pass for nothing.

The picker's menu is asserted on its **visible columns only**: the hidden third
column is the absolute path, which contains both the branch name and the relative
path, so a substring match on the whole menu passes whatever the first two
columns say. Likewise most `gw` cases run from the main root, where the main
checkout and the current worktree coincide. Three run from inside a linked
worktree to tell them apart: one pins which of the two `gw` files new worktrees
under; one that the picker leaves out the main checkout and keeps paths relative
to it; and one that a pick hands `cd` the absolute path, since from the main root
a relative one lands in the same place.

The picker reads `git worktree list --porcelain`, never the human format: that
one splits a path with a space at its first word and quotes and escapes a path
with a backslash, so `cd` lands somewhere else. Two cases build the main checkout
under such a path to pin it — every other fixture lives under a plain temp
directory, where the two formats agree.

The picker leaves out the **main checkout**, which porcelain always lists first,
not a branch called `main`: matching the name offered the main checkout itself in
a repository whose trunk is `master`, and hid a linked worktree that had `main`
checked out. `new_repo` puts the main checkout on `main`, where the two readings
agree, so two cases break that — a trunk named `master`, and `main` checked out
in a linked worktree.

The `[gone]` upstream that `gdmerged` treats as consent is set up for real: push
the branch, delete it in the bare origin, `fetch -p`.

One case is deliberately weaker than it looks — the manually-deleted-worktree case
asserts the outcome, not the `git worktree prune` that opens `gdmerged`, since
`git worktree remove --force` clears the same stale record and the two cover each
other there.

## What `gw` spends its time on

Measured on tetsunavi-monorepo (~9,000 tracked files, a `.worktree-copy`
expanding to ~200 files):

| Phase | Time |
| --- | --- |
| `git worktree add` (the checkout) | ~0.9s |
| `.worktree-copy`, one `check-attr`/`dirname`/`mkdir`/`cp` per file | ~1.7s |
| `.worktree-copy`, as now | ~0.15s |

**The copy's cost was process count, not bytes.** So `_gw_copy_files` asks git
about LFS for every path in one `check-attr --stdin` call, and copies a listed
directory with one `cp -R <dir>/. <dst>` unless an LFS file is inside it —
`/.`, because the checkout may already hold that directory, and a bare source
would land one level below it. Keep new per-file work out of that loop.

The checkout is the floor: parallel checkout (`checkout.workers=0`) measured
no faster here, so it is not set.

## Worktree layout

`gw` nests every worktree under `<checkout>/git-worktrees/`, which makes the main
checkout a **string prefix** of all of them. That is why anything matching a cwd
to a worktree must use longest-prefix ownership rather than containment — see
[bin/pr-review-common.md](../bin/pr-review-common.md).
