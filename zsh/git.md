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

Three things are worth knowing before editing it:

1. **The `mktemp -d` path must be resolved with `:A`** — macOS hands back
   `/var/…`, git reports `/private/var/…`, and without that every path comparison
   is against the wrong prefix *and* `gw`'s "changing directory to repository
   root" branch fires on every call.
2. **The `fzf` stub honours `--accept-nth`**, because `gw` depends on it: the menu
   carries the absolute path in a hidden third column, and a stub returning the
   whole line hands `cd` three tab-separated fields.
3. **The y/N prompt reads `/dev/tty` directly** — deliberately, since the branch
   list already occupies stdin — so **no redirection can answer it**.
   `_gdmerged_confirm` exists purely as the seam a test can override, and both
   answers are exercised through it.

The `[gone]` upstream that `gdmerged` treats as consent is set up for real: push
the branch, delete it in the bare origin, `fetch -p`.

One case is deliberately weaker than it looks — the manually-deleted-worktree case
asserts the outcome, not the `git worktree prune` that opens `gdmerged`, since
`git worktree remove --force` clears the same stale record and the two cover each
other there.

## Worktree layout

`gw` nests every worktree under `<checkout>/git-worktrees/`, which makes the main
checkout a **string prefix** of all of them. That is why anything matching a cwd
to a worktree must use longest-prefix ownership rather than containment — see
[bin/pr-review-common.md](../bin/pr-review-common.md).
