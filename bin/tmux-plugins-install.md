# tmux-plugins-install

`tmux-plugins-install [tmux-plugins.txt]` checks every tmux plugin out in
`~/.tmux/plugins/<repo name>` at the commit `bin/tmux-plugins.txt` names, tpm
included. `bin/init` (macOS, Ubuntu, WSL) and `update-all` run it. It prints
one line per plugin (`at <sha>` or `checked out <sha>`); a plugin that fails
does not stop the rest, and the run exits 1 once they are done, naming each.
Exit 2 is a usage error.

The zsh, Neovim and Go counterparts are [zinit-cooldown.md](zinit-cooldown.md),
[lazy-cooldown.md](lazy-cooldown.md) and [go-cooldown.md](go-cooldown.md).

## Why not tpm

tpm cannot pin a commit (checked against tpm 99469c4, 2026-10):

- `@plugin 'user/repo#ref'` reaches `git clone -b <ref> --single-branch`,
  which takes a branch or a tag, never a SHA. A tag can be moved.
- `prefix + U` is a `git pull` in each clone: the branch's tip as pushed, the
  minute it was pushed.

So tpm is kept only as the loader: `run '~/.tmux/plugins/tpm/tpm'` in
`.tmux.conf` sources each `@plugin`'s directory, wherever its contents came
from. `prefix + I` finds every plugin installed and does nothing; `prefix + U`
fails, because a detached checkout has no branch to pull. A plugin added to
`.tmux.conf` and not to the list would be cloned at its tip by `prefix + I`;
the suite fails until both name it.

**tpack** (tmuxpack/tpack), the successor tpm's README points to, does take
`#<sha>`. It was not adopted (2026-10): the repository was eight months old,
and installed the tpm way it downloads a binary and updates itself, which
puts a younger and stronger dependency in front of the four it would pin.

## The rule

For each `<https URL> <commit>`:

1. **Missing**: `git clone --no-checkout`, then the checkout below.
   Submodules are not fetched: in these plugins they are test libraries.
2. **Not a clone** (a directory without `.git`): error.
3. **Another repository**: the clone's `remote.origin.url` must name the line's
   repository, or it is an error and nothing is checked out. The raw value is
   read, not `remote get-url`, which applies `.gitconfig`'s `insteadOf`. tpm's
   `https://git::@github.com/…` and a trailing `.git` or `/` count as the same.
4. **Commit absent**: one `git fetch origin`; still absent is an error.
5. **Checkout**: `git checkout --force --detach <commit>` unless HEAD is already
   there. `--force` because `.tmux.conf` patches `tmux-fzf-url/fzf-url.sh` with
   `sed -i` on every load, and that edit would refuse a checkout; the next load
   applies it again. Any other local edit in a plugin is lost the same way.

Every line is read before anything is cloned: one that is not
`<url> <40-hex commit>` fails the run.

## Moving a pin

By hand: no cooldown tool reads this list, because four plugins that change a
few times a year do not need one. Read the compare view, take a commit at least
7 days old (the window everything else here uses), and edit the line. The next
`update-all` checks it out.

## Tests

`bin/tmux-plugins-install.test.sh` runs in a container or CI only (`bin/test-in-docker
bin/tmux-plugins-install.test.sh` locally): it never starts tmux, but every
`bin/tmux-*.test.sh` sources `bin/tmux-test-guard.sh`, enrolled by name. Upstreams are local repositories, so no case
reaches the network, and `GIT_CONFIG_GLOBAL=/dev/null` keeps the developer's
`insteadOf` and hooks out. One case runs a copy of the tool through a link, as
`update-all` does; one checks the list against `.tmux.conf`'s `@plugin` lines.
`zsh/update.test.zsh` pins that `update-all` runs it and names its failure.
The real list was checked against this machine's clones, 2026-10: all four at
their pins, tpm-written origins accepted.
