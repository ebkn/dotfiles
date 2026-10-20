# go-cooldown and go-tools-install

`bin/go-tools.txt` lists the Go tools `update-all` and `bin/init` install, each
at a version:

```text
<module> <version> <github repo> <branch> <package>...
```

- `go-cooldown [--days N] [go-tools.txt]` moves each version forward to the
  newest **release** whose commit was already on its branch **N days ago**
  (default 7), by GitHub's own record of pushes. It prints one line per
  module, rewrites only the versions that move, and commits nothing: the diff
  is left to be read and committed.
- `go-tools-install [--except <module>]... [go-tools.txt]` runs
  `go install <package>@<version>` for every package. A failed install does
  not stop the rest; it exits 1 once they are done, naming each.

`update-all` runs the cooldown, then the install, whether or not the cooldown
decided every module: a module it held stays at the version vetted before. The
init scripts run only the install (`install_go_tools`); WSL leaves out
`tailscale.com`, as it always did.

The zinit and lazy.nvim counterparts are [zinit-cooldown.md](zinit-cooldown.md)
and [lazy-cooldown.md](lazy-cooldown.md); all three share `bin/cooldown.zsh`.

## Why not `@latest`

`go install …@latest` built and ran a release the minute it was published,
and `tailscale…@main` whatever was pushed last. The module proxy and the
checksum database make a published version immutable, which stops a tag
being moved under it later; they do nothing about a hijacked account
publishing a new one.

## The rule

For each line, newest release first, after the pin only:

1. **Releases only**: `go list -m -versions` (which leaves out retracted
   versions itself), minus pre-releases.
2. **Its commit, from the proxy**: `Origin.Hash` in the version's `.info` from
   the first `GOPROXY` entry. What `go install` builds is what the proxy
   served, not what the tag points at today. A proxy URL that is not `https`
   or `file` (`direct`, `off`) stops the run before anything is asked.
3. **The right repository**: when `Origin.URL` is on GitHub, it must be the
   line's repository. `golang.org/x/tools` comes from
   `go.googlesource.com`, so its GitHub mirror, `golang/tools`, is asked: a
   commit hash is the same in both.
4. **On its branch N days ago**: the branch's tip at the cutoff, from GitHub's
   activity log (`tip_at`), contains the commit. `{X.Y}` in the branch is the
   release's own major.minor: tailscale cuts `v1.104.1` from
   `release-branch/1.104` and never merges it into `main`, and gopls cuts
   `v0.23.0` from `gopls-release-branch.0.23`. A branch with no
   tip at the cutoff -- created since, or deleted -- holds no release.

The first release that passes is taken. **Not the release's `Time`**: the
proxy's, and deps.dev's `publishedAt` with it, is the commit's date, which
whoever made the commit sets. The proxy's own first-seen time is only in
`index.golang.org`'s feed of every module, 2,000 entries per 9 minutes, which
cannot be asked about one module (checked 2026-10).

| Line | Meaning |
| --- | --- |
| `moved <old>..<new> (on <branch> N days ago) <compare URL>` | the version in the file was rewritten |
| `up to date (<version>)` | no release follows the pin |
| `stays: no release after <version> was on its branch N days ago` | newer releases exist, none vetted yet |
| `error: …` | a call failed, the proxy got the release elsewhere or records no commit for it, the pin is not a listed release (retracted?), or the rewrite was unsafe; that module is untouched |

Exit status: 0 when every module was decided, 1 when any ended in `error` or
the file could not be read, 2 on a usage error.

## Adding a tool

Add its line with the version it should start from, and run `go-cooldown`
before committing: a starting version that is not a release is an `error`. The
branch is the one its releases are tagged on: the default branch for most,
which `gh api repos/<repo> --jq .default_branch` gives.

## gopls, and coc-go's own installer

coc-go installs gopls itself unless `go.goplsPath` names one: once a day at
startup it compares the newest `gopls/` tag with the installed version and runs
`go install golang.org/x/tools/gopls@latest` (`go.checkForUpdates` defaults
to `install`), and it does the same when gopls is missing (coc-go 1.3.35,
`lib/commands.js` and `lib/extension.js`). `vim/nvim/coc-settings.json` points
it at `~/go/bin/gopls`, which `go-tools-install` builds from this list, and
that one setting turns off both. A missing gopls is then an error message, not
an install.

## What it does not cover

- The tools' own dependencies: each is built from its `go.sum`, as published
  with the release that passed.
- The Go toolchain, which Homebrew installs, and a `toolchain` line in a
  tool's `go.mod`, which `go install` may download.
- A release that was on its branch a week, malicious all along.

## Requirements

`go`, `curl`, `jq` and `gh`, authenticated.

## Tests

`bin/go-cooldown.test.zsh`: `gh` and `go` are stubs first on `PATH`, as in
[lazy-cooldown's suite](lazy-cooldown.md#tests), and the proxy is a directory
named by a `file://` `GOPROXY`, which curl reads. `bin/go-tools-install.test.sh`:
`go` is a stub that logs; one case runs the tool through a link, as
`update-all` does, and reads the real `go-tools.txt`.
`bin/init/install-helpers.test.sh` pins that `install_go_tools` hands its
arguments to `go-tools-install`. The lookups themselves
were checked by running `go-cooldown` against all 13 tools, and against gopls
alone when it was added, 2026-10.
