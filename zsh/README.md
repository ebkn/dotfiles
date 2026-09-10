# zsh/ — shell configuration

Modules sourced from `.zshrc`. Identify the correct module rather than editing
`.zshrc` directly; `.zshrc` itself should only hold top-level shell options and
`source` lines. Environment variables that must be set early go in `.zshenv`.

Per-module notes: [ssh.md](ssh.md), [git.md](git.md), [alias.md](alias.md).

## Module order is not fully free, and the constraint is invisible

zsh expands aliases when it *parses* a function body, so **a module defining an
alias must be sourced before any module whose functions use that name.**

Concretely `alias.zsh` must precede `git.zsh`: `alias mkdir='mkdir -p'` is what
makes the `mkdir -p` calls inside `gw()` become `mkdir -p -p`.

Reordering changes the stored function body with no error and no output; the only
way to see it is `print -r -- $functions[gw]`. The comment at the top of `.zshrc`
names the three lines that cannot move.

## `.zshrc` finds `zsh/` relative to itself

Via `DOTFILES="${${(%):-%N}:A:h}"`, so a checkout anywhere loads *its own*
modules — pointing `~/.zshrc` at a git worktree used to still load the main
checkout's `zsh/`, which is the opposite of what testing a change in a worktree
is for.

**Use `${(%):-%N}`, never `$0`.** `$0` is this file only while `functionargzero`
is on and `posixargzero` is off; when it is not, `$0` is the *shell's* name and
`${0:A:h}` resolves it against `$PWD`, so every `source` line points into
whatever directory the shell started in.

Nothing about that is visible — the shell starts, sources nothing, and just has
no configuration. Worse, when `$PWD` happens to be a checkout (running `zsh` from
inside this repo) the `[[ -d $DOTFILES/zsh ]]` guard passes and it loads the
*wrong* modules.

`%N` is correct under all three settings, verified. The guard's fallback to
`$HOME/dotfiles` is what keeps a shell that resolves neither from starting bare.

Pinned by `zsh/zshrc-resolve.test.zsh`.

## Never `stat` a path under `/home` on macOS

`/etc/auto_master` maps `/home` to autofs, so any access under it wakes
`automountd`: measured here at **~16ms per stat**, against ~1ms for an ordinary
missing path.

`.zshenv` probed `/home/linuxbrew/.linuxbrew/bin` unconditionally and paid that
on **every** zsh start — and `.zshenv` is read by non-interactive `zsh -c` too,
so it landed on every git hook and, because `display-popup` runs its command
through `default-shell`, on every tmux popup. It was the largest single item in
`prefix + a`'s latency.

Guarding the probe on `$OSTYPE` took `zsh -c true` from 25.7ms to 5.7ms, against
a 5.3ms floor for an empty `.zshenv`.

**The trap is that removing the guard breaks nothing observable** — `PATH` comes
out identical and no error is printed, everything is merely slower — which is why
`zsh/zshenv-autofs.test.zsh` asserts on whether the probe *executes*.

Prefer `$OSTYPE` over `uname` for such guards: zsh sets it internally, so it
costs no process.

## Other conventions

- **Tmux auto-start**: `.zshrc` starts tmux automatically and exits the shell
  when tmux closes.
- **Lazy loading**: language managers and CLI tools (nvm, pyenv, rbenv, swiftenv,
  gcloud, kubectl, npm, aws) are lazy-loaded via function-wrapping in
  `zsh/lang.zsh` for fast shell startup. Consequence: the bare `aws` may not
  resolve in a non-interactive shell — use `/opt/homebrew/bin/aws`.
- **Plugin manager**: Zinit (`zsh/plugin.zsh`).

## Testing

`zsh -n` over every module is part of `bin/lint-shell`. The unit tests run in CI
(`lint-and-test.yml`).

| Test | Covers |
| --- | --- |
| `zshrc-resolve.test.zsh` | which directory `.zshrc`'s `source` lines resolve to |
| `zshenv-autofs.test.zsh` | the `$OSTYPE` guard on the Linuxbrew probe |
| `ssh-parse-argv.test.zsh` | which argv element is the host — see [ssh.md](ssh.md) |
| `ssh-decorate.test.zsh` | the pane decoration pair being exact inverses |
| `ssh-keepalive.test.zsh` | the keepalive ping's lifetime |
| `his.test.zsh` | `his()` and `gs()` — see [alias.md](alias.md) |
| `rm.test.zsh`, `fd.test.zsh` | the two `alias.zsh` wrappers |
| `git-worktree.test.zsh` | `gw()` and `gdmerged()` — see [git.md](git.md) |

After changing shell config, verify with a new shell session or
`source ~/.zshrc`. Startup profiling can be enabled by uncommenting the `zprof`
lines in `.zshenv` and `.zshrc`.

### zshrc-resolve.test.zsh

Builds a throwaway checkout — a **copy** of the real `.zshrc` (a symlink back
into this repo is exactly what `:A` would follow, defeating the point) next to a
`zsh/` of stubs that announce where they were loaded from — links `$HOME/.zshrc`
at it, and starts `zsh -d -i` with `TMUX` set, because `.zshrc` otherwise starts
tmux and exits before reaching a single `source` line.

The module list is scraped from `.zshrc` with a **loose** pattern on purpose:
tying it to the `"$DOTFILES"` spelling would make a regression fail with "no
source lines found" instead of failing the assertion that names the directory.

Both halves were confirmed red — the old hardcoded `$HOME/dotfiles` form, and
`${0:A:h}` under `posixargzero`.

### zshenv-autofs.test.zsh

Asserts on whether the `/home` stat **executes**, read out of `setopt xtrace`,
rather than on elapsed time — a timing assertion is exactly the kind that goes
flaky on a loaded machine and in CI, and the thing worth pinning is the access,
not the milliseconds.

`$OSTYPE` is a plain parameter, so both branches are driven from either platform
and the macOS and Linux runs assert the same thing.

The PATH assertions alongside it are deliberately weaker than they look: on a Mac
`/home/linuxbrew` does not exist, so the Linux branch adds nothing either way,
and the expectation is derived from the filesystem rather than hard-coded.

Confirmed red by deleting the guard — only the xtrace case fails, which is the
point of having it.
