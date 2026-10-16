# zinit-pins

`bin/zinit-pins [plugin.zsh]` prints the commit pins in `zsh/plugin.zsh`, one
`<owner/repo> <sha>` per line — zinit first, then each plugin in file order.
Without an argument it reads the `zsh/plugin.zsh` of the checkout it lives in.

Why the pins exist, and how zinit treats them, is in
[zsh/README.md](../zsh/README.md#zinit-and-every-plugin-are-pinned-to-a-commit).

## Why one reader

How a pin is written is a convention of `plugin.zsh`, not of zinit:

- zinit is pinned by `_zinit_repo=` and `_zinit_pin=` assignments, because it
  is not a plugin and takes no ice;
- a plugin's pin is the `ver"<sha>"` on the `zinit ice` line before its
  `zinit light|load`, with only comments and blank lines in between;
- either quote is accepted around the SHA, and the SHA is the full 40 hex.

`zsh/plugin.test.zsh` and the pin updater both need that, so it is written
once, here. A second copy would drift: one side learns inline ices or a
renamed repository, the other keeps passing over them.

## It refuses rather than skips

Every line of `plugin.zsh` that starts with `zinit` must be an ice or a
`light`/`load`, and every plugin must carry a full SHA; otherwise the reader
exits 1 and names each problem on stderr, printing nothing on stdout.

The alternative — listing the pins it understood — is the dangerous one. A
caller that moves pins would leave a plugin it never saw where it is, and a
plugin that is not updated looks exactly like one that is up to date. So a
form this reader does not know (`zinit snippet`, `zinit for`, ices written
inline as `zinit wait light …`) is a failure until the reader is taught it.

## Not on `PATH`

It is not linked into `~/.local/bin`: its callers are in this repository and
find it next to themselves. A link would only add a way to go stale when it
moves (see the root CLAUDE.md on `bin/`).

## Tests

`bin/zinit-pins.test.zsh`: the order and shape of the output, indented lines,
either quote, and each refusal — a plugin without a pin, a short SHA, an ice
cut off from its plugin by other code, an unreadable `zinit` form, a missing
`_zinit_pin`, a missing file. The last case runs it through a symlink with no
argument, so that finding its own checkout's `plugin.zsh` is pinned too.
