# zinit-cooldown

`zinit-cooldown [--days N] [plugin.zsh]` moves each commit pin in
`zsh/plugin.zsh` forward to the newest **release tag** whose commit was
already on the repository's default branch **N days ago** (default 7), by
GitHub's own record of pushes. It prints one line per repository and rewrites
only the pins that move. `update-all` runs it, then `zinit update --all`.

Why the pins exist: [zsh/README.md](../zsh/README.md#zinit-and-every-plugin-are-pinned-to-a-commit).
How they are read: [bin/zinit-pins.md](zinit-pins.md).

## The rule

For each `<owner/repo> <sha>` that `bin/zinit-pins` lists:

1. **Candidates** are release tags, newest first — published GitHub Releases,
   drafts and pre-releases left out. A repository without releases offers its
   tags, highest version first (`0.10.0` above `0.9.0`).
2. **The gate**: a candidate passes when its commit is contained in the
   default branch's tip as of the cutoff. That tip is the `after` of the
   newest push GitHub's activity log records at or before the cutoff. The
   first candidate that passes is the eligible one.
3. **Forward only**: the pin moves to the eligible commit when that commit is
   ahead of the pin; the same commit is up to date; behind or diverged stays,
   and the line says which tag it was.

Each line is one of:

| Line | Meaning |
| --- | --- |
| `moved <old>..<new> (<tag>) <compare URL>` | the SHA in `plugin.zsh` was rewritten |
| `up to date (<tag>)` | the pin is the eligible commit |
| `stays: <tag> (<sha>) is behind the pin …` | eligible, but moving there would go back |
| `stays: no release tag was on <branch> N days ago` | every candidate fails the gate |
| `stays: no tags` | nothing to choose from |
| `stays: no push to <branch> older than N days on record` | the gate cannot be computed |
| `error: …` | a call failed or the rewrite was unsafe; that repo is untouched |

Exit status: 0 when every repository was decided, 1 when any ended in `error`
or the pins could not be read, 2 on a usage error.

## Why tags, and why the gate does not trust them

A release tag is the maintainer saying "this is a version", which a commit on
the default branch is not — so a tag is the candidate. But nothing about a
tag's time can be trusted:

- a lightweight tag has no date, and an annotated tag's date is whatever its
  author wrote, like a committer date;
- **a tag can be moved**, and a Release keeps its old `published_at` when it
  is — moving an existing tag onto a new commit is how tj-actions/changed-files
  was compromised;
- GitHub's activity log does not record tag pushes at all (checked against
  zinit and zsh-completions, 2026-10).

So the gate never asks when a tag was made. It asks whether the tagged
commit was already on the default branch N days ago, by a time GitHub
records and a pusher cannot set. A tag moved onto a fresh commit fails it,
because the default branch as it was a week ago does not contain that commit;
so does a tag on a commit that never reached the default branch.

What remains is a maintainer's account itself compromised, a malicious commit
sitting on the default branch unnoticed for N days, and then tagged. Signed
tags would close that; almost none of these repositories sign.

## Why it holds rather than guesses

Every way of not knowing ends in `stays` or `error`, never in a move:

- the activity log is empty or every recorded push is newer than the cutoff
  (`chrissicool/zsh-256color`, untouched since 2022, has no history at all):
  the tip at the cutoff is unknown;
- the releases list cannot be read: falling back to tags would choose by a
  different rule without anyone deciding to;
- the old SHA appears on more than one line of `plugin.zsh` (a comment that
  quotes it, say): the rewrite is a plain substitution and would change both.

Moving a pin **back** is never done here, either. Going back is sometimes
right — a pin taken without the gate — but it is a decision for a person,
made by editing `plugin.zsh`.

## Requirements

`gh`, authenticated (`gh auth status`), and `jq`. A call that fails is an
`error` for that repository; the others are still decided.

## Tests

`bin/zinit-cooldown.test.zsh` serves every `gh api` call from files a case
writes, through a `gh` first on `PATH`; an endpoint a case did not serve fails
like a 404, so a forgotten one cannot pass as "nothing there". Timestamps are
written relative to the real clock, so the tool needs no way to be told the
time. The tool is run as `zsh -f`: through its `env zsh` shebang it would read
`~/.zshenv`, which rebuilds `PATH` with the real `gh` first — the suite's
first run asked GitHub about the fixture repositories that way.
