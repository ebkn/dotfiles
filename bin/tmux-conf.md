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

## Testing (`tmux-conf.test.sh`)

**The load-bearing discovery: `tmux -f <conf> new-session` swallows config errors
entirely** — exit 0, empty stderr, nothing in `show-messages`. Verified by
feeding it an unknown option and a `bind` with no arguments.

`source-file` is the form that reports: it prints `<file>:<line>: <error>` *and*
exits non-zero. So the test starts a server with `-f /dev/null` and sources the
config into it.

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
