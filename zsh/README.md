# zsh/ — shell configuration

Modules sourced from `.zshrc`. Identify the correct module rather than editing
`.zshrc` directly; `.zshrc` itself should only hold top-level shell options and
`source` lines. Environment variables that must be set early go in `.zshenv`.

Per-module notes: [ssh.md](ssh.md), [git.md](git.md), [alias.md](alias.md).

## Module order is not fully free, and the constraint is invisible

zsh expands aliases when it *parses* a function body, so **a module defining an
alias must be sourced before any module whose functions use that name.**

Concretely `alias.zsh` must precede `git.zsh`: `alias mkdir='mkdir -p'` is what
makes the `mkdir -p` calls inside `gw()`'s copy helpers (`_gw_copy_files`,
`_gw_copy_entry`) become `mkdir -p -p`.

Reordering changes the stored function body with no error and no output; the only
way to see it is `print -r -- $functions[_gw_copy_files]`. The comment at the top of `.zshrc`
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

## `update-all` warns about uptime on macOS 26.0–26.3

On those releases the kernel's TCP clock stops **49.7 days after boot**, and a
reboot is the only way back. `calculate_tcp_clock()` (XNU,
`bsd/netinet/tcp_subr.c`) recomputes `tcp_now` — 32-bit milliseconds — from
uptime and stores it only `if (tmp < current_tcp_now)`. Once the value wraps,
that is never true again. `TIME_WAIT` sockets stop being reaped, the 16,384
ephemeral ports leak away, and some days later every outbound connection fails
at once.

Measured on a 26.1 machine up 61 days: 45,327 sockets in `TIME_WAIT`, every one
still there 75 seconds later against a 30-second timeout, and `git pull` failing
with `Can't assign requested address`. **Ping still works** — ICMP needs no
port — so it reads as a broken remote rather than a broken machine.

**macOS 26.4 fixed it, and updating is the real answer.** Read tag by tag in
`apple-oss-distributions/xnu`:

| XNU tag | macOS | How `tcp_now` advances |
| --- | --- | --- |
| `xnu-11417.*` | 15 | `tcp_now += incr` — wraps harmlessly |
| `xnu-12377.1.9` to `.81.4` | 26.0–26.3 | `if (tmp < current_tcp_now)` — freezes |
| `xnu-12377.101.15` onwards | 26.4+ | `if (TSTMP_LT(tmp, current_tcp_now))` — modular |

(26.4.1 was observed running `xnu-12377.101.15`; the earlier tags are matched to
releases by their numbering.)

So `_uptime_reboot_warning` exists for a machine that stays on an affected
release, and it reads `kern.osrelease` to stay silent everywhere else — on a
fixed kernel it would be a false alarm on every run. It asks the kernel rather
than `$OSTYPE`, which is the release zsh was *built* for.

It runs at the end of `update-all` and speaks from day 30. Three things about it
are deliberate:

- **It warns rather than reboots.** With FileVault on, an unattended restart
  stops at the pre-boot unlock screen, where neither sshd nor Tailscale is
  running, and a remote machine is unreachable until someone types at it.
- **It counts wall-clock uptime, though the kernel counts only time awake**
  (`tcp_now` comes from `mach_absolute_time()`, which does not advance during
  sleep). On a machine that sleeps the warning is early, never late.
- **It is only seen when `update-all` is run.** Day 30 leaves a 20-day window; a
  machine that goes longer than that between runs is not covered.

Pinned by `zsh/update.test.zsh`.

## zinit and every plugin are pinned to a commit

A plugin is sourced into every shell, with SSH keys and `gh`/cloud tokens in
reach, so a compromised push to any of them would run here on the next
`update-all`. `zsh/plugin.zsh` therefore holds each one at a commit, and an
update is a move of that SHA. `update-all` makes the moves itself through
[bin/zinit-cooldown](../bin/zinit-cooldown.md) and zinit follows at once, so
what guards it is the cooldown, not a review; the rewritten `plugin.zsh` is
left uncommitted, for the diff to be read and committed afterwards.

- **Plugins**: a `ver"<SHA>"` on the plugin's `zinit ice`.
- **zinit itself** is not a plugin and takes no ice. `_zinit_pin` holds it: each
  start `read`s `.zinit/bin/.git/HEAD` (no fork) and, only when it differs,
  checks the pin out detached, fetching first if the clone lacks it. Detached
  also makes zinit's self-update a no-op, because it pulls only a branch with an
  upstream — so `zinit update --all` cannot move it either. When the pin cannot
  be checked out (offline after a bump) the shell still starts, and says on
  stderr that zinit is running unpinned.

To update: `update-all` runs [bin/zinit-cooldown](../bin/zinit-cooldown.md),
which moves each pin forward to a release tag already on its default branch a
week ago, then `zinit update --all`. By hand: change the SHA, then
`zinit update <plugin>` for a plugin, or start a new shell for zinit.
Behaviour verified against zinit `f466c88` and `db9e267` (v3.17.0), 2026-10:

| Action | Result |
| --- | --- |
| install with `ver"<SHA>"` (full or short) | checked out at the pin |
| `zinit update`, pin unchanged | stays |
| `zinit update` after moving the pin forward | moves to the new pin |
| `zinit update` from a shell that has not loaded the plugin | stays: the ice is stored in `._zinit/ver` |
| **move the pin back** (to an ancestor), then `zinit update` | **stays on the newer commit** — the update is `git pull --ff-only origin <sha>`, and pulling an ancestor is "Already up to date"; check the pin out by hand in `~/.zinit/plugins/<owner>---<repo>` (zinit itself goes back on its own, at the next shell start) |
| **remove `ver`**, then `zinit update` | **still stays** — the stored ice outlives the line; `zinit delete` and reinstall to unpin |
| **`ver"<SHA>"` with `depth"1"`** | **unpinned, silently** — see below |

**Never put `depth` on a pinned ice.** The shallow clone does not contain an
older commit, so the checkout fails — and the clone is left at the newest
commit. zinit `f466c88` prints `Cannot check out … (ver ice)` once, on the
install; v3.17.0 does not even do that. Every shell after it loads the
unpinned code without a word.

`zinit update` lists the upstream commits it found even when the pin keeps it
from moving to them. The list is not what was installed; the plugin's
`git rev-parse HEAD` is.

Pinned by `zsh/plugin.test.zsh`.

## npm globals install with their scripts off

`update-all` and `bin/init/common.sh`'s `install_or_upgrade_npm_global` leave
install scripts to `~/.npmrc`'s `ignore-scripts=true`. They used to pass
`--ignore-scripts=false`, on the belief that `@openai/codex` builds its binary
in a postinstall; it no longer does (its binaries are optional dependencies),
and the override ran every script in every global's tree, under this user.

Checked 2026-10 by installing the whole list with `--ignore-scripts` into a
scratch prefix: of 380 packages only `yarn` declares one, a `preinstall` that
removes a Corepack `yarn` link, which Volta does not make. A global added later
that does need its script is installed by hand with `--ignore-scripts=false`,
or gets the flag on its own line here, with the reason.

## Other conventions

- **Tmux auto-start**: `.zshrc` starts tmux automatically and exits the shell
  when tmux closes.
- **Lazy loading**: `nvm`, `gcloud` and `kubectl` are lazy-loaded via
  function-wrapping in `zsh/lang.zsh` for fast shell startup.
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
| `ssh-keepalive.test.zsh` | the keepalive ping's lifetime, one per host |
| `his.test.zsh` | `his()` and `gs()` — see [alias.md](alias.md) |
| `rm.test.zsh`, `fd.test.zsh` | the two `alias.zsh` wrappers |
| `git-worktree.test.zsh` | `gw()` and `gdmerged()` — see [git.md](git.md) |
| `update.test.zsh` | which releases and uptimes `update-all`'s warning speaks on, that `update-all` still ends with it, the order of its lazy.nvim and Go steps, the guard on its restore, the list of failed pin steps, and that npm runs with install scripts off |
| `plugin.test.zsh` | that every plugin and zinit carry a commit pin, no ice has `depth`, and zinit is held at its pin |

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

### update.test.zsh

`sysctl` and `date` are functions, so a case chooses the release and the uptime.
The `sysctl` stub answers per OID — one value per line, in the order asked — so
no case depends on whether the function reads its two values in one call.

Most of the expectations are *silence*, which is also what a function that never
ran produces. So every case captures stderr: a missing or crashing function
prints `command not found` and fails them, rather than passing as quiet.

Four cases earn their keep:

- **The lazy.nvim steps run clean, `lazy-cooldown`, restore**, the restore in
  an nvim of its own: the reason is in
  [bin/lazy-cooldown.md](../bin/lazy-cooldown.md#only-restore-may-run-after-the-rewrite).
  `nvim` is a function logging each argument quoted, so an unquoted
  `+Lazy! clean`, which splits into two arguments, fails it too. Beside it,
  `_lazy_restore`'s cases point `XDG_CONFIG_HOME` at a fixture lockfile and
  have the `nvim` function rewrite it, as an install at startup would.
- **`update-all` ends with the warning.** The function can pass every case of
  its own while `update-all` no longer calls it — and a warning that stopped
  firing looks exactly like a healthy machine. The case runs the real
  `update-all` with an empty `path`: it names every tool bare, so each becomes
  `command not found` and nothing on the machine is touched. **A line that named
  a tool by absolute path would run for real there.** Confirmed red by deleting
  the call.
- **The real `kern.boottime` parses** (macOS only, and it says so when skipped
  on the Linux runner). The stub is a hand copy of what one Mac printed, and the
  first manual check proved nothing: on a machine up two days the function is
  silent whether it parsed the boot time or failed to. So the case feeds the
  real line through with the clock set to the year 2286.
- **Both edges of the gate**: Darwin 25.0 and 25.3 warn, 24.x and 25.4 do not.

### plugin.test.zsh

The plugin pins are checked statically: running zinit against GitHub would
make the suite depend on the network, and what fails is a line in
`plugin.zsh`, not zinit. The zinit pin is run for real, against a local
repository whose `zinit.zsh` defines a logging stub, with the copy of
`plugin.zsh` changed only in its pin.

Whether a start ran git, and whether it fetched, is read from a `git` first on
`PATH` that logs each call and hands over to the real one. Neither shows any
other way: the fetch's failure is silenced, and a checkout of a commit already
in the clone succeeds with or without it. An unreachable remote was tried first
and proved nothing for that reason. The already-pinned case asserts that git is
not run at all — the cost guarded is a fork, and worse a network call, on every
shell. The bumped cases add a commit after the clone was made, so that the
fetch, and its failure offline, are actually reached.

Reading the pins is left to [bin/zinit-pins](../bin/zinit-pins.md), which
refuses any `zinit` line it cannot read (`snippet`, `for`, inline ices); this
suite holds it to the real file and checks it returned one pin per plugin plus
zinit's. `depth` fails on any line that is not a comment.

Confirmed red against the unpinned `plugin.zsh` and `update.zsh`, against a
start that skips the HEAD comparison (git is run while pinned), and against one
that always fetches.
