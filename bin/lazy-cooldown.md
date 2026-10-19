# lazy-cooldown

`lazy-cooldown [--days N] [lazy-lock.json]` moves each commit in
`vim/nvim/lazy-lock.json` forward to the tip its branch had **N days ago**
(default 7), by GitHub's own record of pushes. It prints one line per plugin
and rewrites only the pins that move. `update-all` runs `Lazy! clean`, then
it, then `Lazy! restore` in an nvim of its own, which checks every plugin out
at its lockfile commit. It commits nothing: the rewritten lockfile is left for its
diff to be read and committed.

The zsh counterpart, and the reasoning both share about the gate, is
[bin/zinit-cooldown.md](zinit-cooldown.md). The two share their gate code in
`bin/cooldown.zsh`.

## Why `Lazy! sync` had to go

lazy.nvim's `sync` and `update` ignore the lockfile: they check out each
branch's tip as it is now and write those commits *into* the lockfile, so a
commit pushed a minute earlier ran on the next start. Only `restore` (and the
install of a missing plugin at startup) reads it. lazy.nvim has no cooldown of
its own yet: folke/lazy.nvim#2141, and the `commit` hook of PR #2165 (both
open, 2026-10).

## Only `restore` may run after the rewrite

When a clean or an install finishes, lazy.nvim rewrites the lockfile from the
commits *installed*, and keeps that in memory for the rest of the process.
`nvim '+Lazy! clean' '+Lazy! restore'` therefore restores to the old pins:
the clean writes them back over the rewrite, the restore reads them, nothing
moves and nothing fails (found by hand, 2026-10, stepping back three pins).
An install at startup, of a plugin missing from disk, does the same. So
`update-all` cleans in one nvim, whose startup also installs what is
missing, and restores in another after `lazy-cooldown`;
`zsh/update.test.zsh` pins that order.

## The rule

For each `<name> <branch> <commit>` in the lockfile:

1. **Which repository**: lazy.nvim is asked (`nvim --headless`), since a
   spec's `name`, `url` and `dependencies` all decide it. Only GitHub URLs.
2. **The candidate**: the branch's tip at the cutoff, which is the `after` of
   the newest push to *that* branch the activity log records at or before
   it. The branch is the lockfile's, not the default one: coc.nvim follows
   `release`.
3. **Forward only**: it moves when the candidate is ahead of the pin.
4. **Still there**: and only when the branch still contains it. lazy.nvim
   fetches branches, so a commit force-pushed off one cannot be checked out.

Unlike zinit-cooldown, the candidate is not a release tag. Most of these
plugins have none (14 of 41), or tags years behind the branch they are used
from (coc.nvim's last is from 2022). With tags first, those would never move.
What the gate vouches for is the same either way: the commit sat public on the
branch for N days.

| Line | Meaning |
| --- | --- |
| `moved <old>..<new> (<branch> N days ago) <compare URL>` | the commit in the lockfile was rewritten |
| `up to date (<branch> N days ago)` | the pin is that tip |
| `stays: <branch> N days ago (<sha>) is behind the pin …` | the pin is newer than the cutoff: taken by hand or by `Lazy update`, not vetted |
| `stays: <branch> N days ago (<sha>) has diverged from the pin …` | the branch was rewritten under the pin |
| `stays: <sha> is no longer on <branch>` | force-pushed away since the cutoff |
| `stays: no push to <branch> older than N days on record` | the tip at the cutoff is unknown |
| `stays: no <branch> branch N days ago (deleted or renamed)` | GitHub records a rename as a deletion: change the lockfile's branch by hand (below) |
| `error: …` | a call failed, lazy.nvim does not list the plugin, its URL is not on GitHub, or the rewrite was unsafe; that plugin is untouched. Right after a branch rename, too, when the pin would move (below) |

Exit status: 0 when every plugin was decided, 1 when any ended in `error` or
the lockfile or plugin list could not be read, 2 on a usage error.

## A renamed branch

Editing the lockfile's `branch` is not enough on its own. lazy.nvim writes the
lockfile back after a restore, and for a detached checkout it takes the branch
from the clone's `origin/HEAD`, which a clone made before the rename still
points at the old name. So the old branch comes back. On each machine that has
the clone, run `git -C ~/.local/share/nvim/lazy/<name> remote set-head origin
--auto` before the restore (rust.vim, `master` to `main`, 2026-10).

Until the rename is N days old, it does not read as one: the candidate is
still the old branch's tip at the cutoff. When that is the pin, the line is
`up to date`; behind or diverged, the matching `stays`, and neither mentions
a rename. Only when the pin would move does checking that the tip is still on
the branch ask GitHub about a name that is gone: `error: cannot compare <sha>
with <old branch>`, exit 1. Once the rename is older than the cutoff, every
case becomes the `stays: no <branch> branch` hold. That window was accepted
(2026-10) rather than given a case of its own.

## What it does not cover

- `:Lazy update` and `:Lazy sync` typed by hand still take the branch tips,
  and write them into the lockfile; the next run reports those pins as
  `behind`, and does not move them back.
- A plugin added to the specs installs at its tip on the next start, as
  lazy.nvim does for any plugin missing from the lockfile.
- `CocUpdate` and `TSUpdate`, which `update-all` also runs, fetch coc
  extensions from npm and treesitter parsers; neither goes through here.

## Requirements

`gh`, authenticated, `jq`, and `nvim` with this config. The `nvim --headless`
run starts the whole config, so a plugin printing to stdout shares the line
with the first record (image.nvim does); records are found anywhere in a line.
That Lua is run only for real, never by the suite; checked by hand against
the 41 plugins, 2026-10.

## Tests

`bin/lazy-cooldown.test.zsh`: `gh` and `nvim` are stubs first on `PATH`, as
in [zinit-cooldown's suite](zinit-cooldown.md#tests), and it is run as
`zsh -f` for the same reason.
