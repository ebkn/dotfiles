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

`zsh/plugin.test.zsh` and [bin/zinit-cooldown](zinit-cooldown.md) both need that, so it is written
once, here. A second copy would drift: one side learns inline ices or a
renamed repository, the other keeps passing over them.

## It refuses rather than skips

Every line of `plugin.zsh` that runs `zinit` must be an ice or a
`light`/`load` (words split by any whitespace), every plugin must carry a full
SHA closed by the quote it opened with, and every ice must be followed by its
plugin; otherwise the reader exits 1 and names each problem on stderr,
printing nothing on stdout.

"Runs `zinit`" is judged on the line's shell words, comments dropped: a word
that is zinit's name — bare, `\zinit`, `'zinit'`, `"zinit"` — or that opens a
command substitution with it (`` `zinit … ` ``, `$(zinit …)`). So zinit as part
of another command (`[[ -n $X ]] && zinit light …`) is caught, which a check of
the line's start alone passed over, while `zinit` inside a quoted string
(`print "… zinit's pin …"`, in `plugin.zsh` itself) is one word that runs
nothing. An ice line holding a control operator (`;`, `&&`, `|`, …) is
refused: `zinit ice ver"…"; zinit light b/two` hands the ice to `b/two`, and
the plugin on the next line loads unpinned.

`eval` runs a string, which the split keeps as one word, so on a line with
`eval` any mention of zinit counts as running it. A substitution — `$(…)`,
backquotes, `<(…)`, `>(…)`, `=(…)` — is one word too, and what runs inside it
(`$(true; zinit light …)`, `$(eval "zinit …")`) is out of reach of the checks on
the line's words, so a substitution mentioning zinit anywhere counts the same
way.

**The limit:** this is a static reader. zinit reached through an alias, a
wrapper function, a sourced file, a variable holding its name
(`z=zinit; $z light …`) or a name escaped mid-word (`zi\nit`) is not seen, and
such a plugin is silently left out.
`plugin.zsh` uses none of these, and should not start to; the reader cannot
be taught them without running the file.

A plugin line is read only when it is the whole line:
`zinit light <owner/repo>`, then nothing but an optional comment. So
`zinit light a/one && zinit light b/two`, a `\` continuation and a quoted name
are refused too — each once came out as a pin with the second plugin dropped
or a name that was not a name. `_zinit_repo` and `_zinit_pin` must each appear
once and hold only an `owner/repo` and a full SHA.

The ice is read the same way, as words: the shell's own split of the line,
comments dropped. A plugin is pinned only when exactly one word is
`ver"<sha>"` or `ver'<sha>'`. Matching the text `ver"…"` anywhere on the line
took a `ver` in a comment (`zinit ice wait # was ver"…"`) or inside another
ice's value as the pin, while zinit loaded the plugin unpinned; and with two
`ver`s, a caller moving the pin could not tell which zinit uses.

Consecutive `zinit ice` lines, which zinit would merge, are not merged here:
the first is an ice with no plugin after it, so the file is refused whichever
of them holds the `ver`.

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

`bin/zinit-pins.test.zsh`: the order and shape of the output, indented and
tab-separated lines, either quote, and each refusal listed above. Every
refusal asserts the status is exactly 1 and stdout is empty — a reader that
printed the pins it understood and then failed is the one this exists to rule
out, and `*exit=1*` would also have matched 126 and 127. One case has several
problems at once, to pin that all are named. The last runs it through a
symlink with no argument, so that finding its own checkout's `plugin.zsh` is
pinned too.
