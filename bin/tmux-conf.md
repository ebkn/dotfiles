# .tmux.conf and tmux-conf.test.sh

Notes on `.tmux.conf` itself. The doc lives here because
`bin/tmux-conf.test.sh` is what pins these.

Per-feature detail is in the script docs: [tmux-agents](tmux-agents.md),
[tmux-agent-view](tmux-agent-view.md), [tmux-popup](tmux-popup.md),
[tmux-cheatsheet](tmux-cheatsheet.md), [tmux-session-swap](tmux-session-swap.md).

## `prefix + d` asks before detaching

Inside an ssh pane the chord is deliberately *not* passed through to the remote
tmux the way `p`/`t`/`o`/`u` are, so a mistyped `d` detaches the client in front
of you and drops you out of everything local — the expensive direction of the
mistake, and an easy one to make while working on a remote.

Popups are exempt (`#{m:_*,#{session_name}}`): there `d` closes a popup, which is
what it looks like it does, and asking on the way out of a view is friction with
nothing to protect.

## The `prefix + w` tree format (`@tree_format`)

`choose-tree -F` controls only the text after each row's `name:`. The `(n)` key,
the tree lines and the name are drawn by tmux and cannot be restyled. The format
is kept in `@tree_format` and passed as `#{E:@tree_format}`, which keeps the
binding line readable. `E:` is required: without it, the option's text would
appear as-is instead of being expanded per row.

A session row reads `● attached` (green) or `○ no tab` (grey). Under the
one-tab-one-session rule, "detached" means no WezTerm tab shows the session, so
it is labelled that way. A symbol accompanies the colour so the difference
survives a theme where green and grey look alike.

Two tmux details, verified on 3.7c by rendering the tree in a nested client and
running `capture-pane`:

- `#{pN:…}` pads on the **right** (left-aligned text), and `#{p-N:…}` pads on the
  left. The window name and its flags are padded as one unit so the flag stays
  attached to the name.
- `#[…]` styles in the format are rendered in tree rows (seen with
  `capture-pane -e`).

## Purple means "another machine" (`@ssh_view`)

The status bar and the active pane border go purple when the screen in front of
you is a remote's, green otherwise. `@ssh_view` is the single condition behind
both; the styles only ask it.

It is true two ways, because the two ends of an ssh connection know different
things:

- `@ssh_host`, set on the local pane by the `ssh()` / `myssh()` wrappers in
  [zsh/ssh.zsh](../zsh/ssh.zsh). This is the only signal this side has.
- a session name matching `local-*`. **The remote tmux has no idea it is being
  looked at down a wire** — and with `myssh` most of what is on screen is drawn
  by *it*: its own status line, its pane borders. So the local `@ssh_host`
  reaches almost none of it. What the remote does have is the session name
  `myssh` asks for, `local-<pane id>`, which exists only because another
  machine's pane created it.

Two consequences worth knowing before changing this:

- **Switch to a differently-named session on the remote and its chrome goes back
  to green.** Nothing about that session records where its viewer is. The name
  is the whole signal; there is no state to be stale, and nothing to clean up.
- Styles are format-expanded, so a conditional works in `status-style` just as it
  does in `pane-active-border-style` — verified against tmux 3.7c by attaching a
  client inside another tmux and capturing the rendered status line with
  `capture-pane -e`. The whole bar changes background, not just the text.

The same distinction is carried into the WezTerm tab bar by `format-tab-title` in
[wezterm.lua](../wezterm.lua), which keys off the `≫` marker that
`set-titles-string` puts in a remote pane's title and paints the tab on the same
palette. Change the marker and the tab colour goes with it, silently.

## Testing (`tmux-conf.test.sh`)

**The load-bearing discovery: `tmux -f <conf> new-session` swallows config errors
entirely** — exit 0, empty stderr, nothing in `show-messages`. Verified by
feeding it an unknown option and a `bind` with no arguments.

`source-file` is the form that reports: it prints `<file>:<line>: <error>` *and*
exits non-zero. So the test starts a server with `-f /dev/null` and sources the
config into it.

**It sources into a fixture `$HOME`, and both reasons matter.** The config's last
two lines reach into the real one:

```
run '~/.tmux/plugins/tpm/tpm'
run-shell 'f="$HOME/.tmux/plugins/tmux-fzf-url/fzf-url.sh"; … sed -i …'
```

Without the plugin manager installed `tpm` exits 127 and `source-file` reports it
on stderr, so a well-formed config failed this case on every machine but the
developer's — which is what it did in CI, invisibly, for as long as an earlier
failure hid the step. The fixture reproduces the precondition with a no-op `tpm`
instead of excusing the line in the captured stderr; excusing it would have
loosened "stderr must be empty" for everything else too, and that strictness is
the whole reason `source-file` is used here.

The second line is the sharper reason: on a machine where that plugin *is*
installed, this test used to **rewrite it in place** with `sed -i`. A test that
needs something installed should supply it, which also takes it out of the real
`$HOME`. `$HOME` is exported before the server starts, because tmux expands `~`
and `$HOME` from the **server's** environment, not the sourcing client's.

A consequence to know before reading a surprising column count below: **the
throwaway server is now deliberately plugin-free on every machine.** It was not
before — a real `tpm` loaded the developer's plugins into it while CI, where the
load failed, had none, so the cheatsheet cases were measuring a different set of
bindings depending on where they ran. `tagged notes reach the running server`
compares `server >= file`, which plugins could only pad; with none it sits at
equality, which is the comparison that was meant.

What it asserts:

- `prefix + d` asks before it detaches. Note `list-keys -T prefix d` returns
  nothing on 3.7 (the key argument is not honoured), so the whole table is listed
  and the row grepped out.
- `C-]` leaves an agent view — read out of the **root** table, since a prefix
  chord there would reintroduce the nested-tmux ambiguity it exists to avoid —
  and `send-keys` the key through outside a view. Both are guarded on
  `_*`/`_agent_*`, so the assertion is on the whole command, not just the target.
- Every non-`-n` binding carries `-N`. A `-n` root binding has no reader, since
  neither `list-keys -T prefix` nor the cheatsheet shows it.
- Every tagged category appears as a heading.
- The page is one column at width 40 and two or three when wide. **Column count
  is measured from the heading rows, not line length**: an entry whose
  description is longer than the terminal, and the fixed footer, both
  legitimately exceed a narrow width.
- The `prefix + w` binding still carries both halves of the swap wiring — see
  [tmux-session-swap](tmux-session-swap.md).
