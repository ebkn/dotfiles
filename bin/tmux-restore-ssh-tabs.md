# tmux-restore-ssh-tabs

`tmux-restore-ssh-tabs <host>` re-opens one WezTerm tab per detached tmux
session on `<host>`, each running `myssh` attached back to that session.

It is the remote counterpart of `tmux-restore-tabs`. That one covers WezTerm
dying while the local tmux survives; this one covers the local side being lost
entirely — a reboot, a killed local tmux server, a different client machine —
while the remote sessions live on, detached, with nothing reconnecting to them.

## Why plain `myssh <host>` cannot do it

`myssh` names the remote session after the local pane (`local-<pane id>`). A
restored tab is a new pane, so it would connect under a new name, and
`new-session -A` would create a fresh empty session beside the one it was meant
to restore — with no error. `MYSSH_SESSION=<name>` overrides the name (see
`zsh/ssh.zsh`); this script is what sets it.

## Why the remote has to `adopt`, not just list

Each restored tab connects with conn_id = the session's name. But the remote
still holds `tmux-track-session` records from the old connections, and those can
cross: conn `local-5` last visited session `local-9` (e.g. via `prefix + w`).
Followed as they are, tab `local-5` lands in `local-9`, tab `local-9` joins it
there, and session `local-5` never gets a tab — two tabs mirroring one session,
silently.

So `tmux-track-session adopt` lists the free sessions **and** claims each one for
a conn_id of its own name, releasing it from every other record. After that,
every tab maps to exactly one session, and later autossh reconnects keep
following the session the tab actually moves to, as usual.

What `adopt` skips: attached sessions (another client owns them), popup sessions
(`_*`, never had a tab), and names containing `/` (the name becomes a file name
in the state directory).

**The remote must run a `tmux-track-session` that knows `adopt`.** An old one
prints its usage and exits 1, and the script stops there rather than reading the
empty output as "nothing to restore".

## How a tab is made

For each session: a detached local tmux session, `MYSSH_SESSION=<s> myssh <host>`
typed into its shell with `send-keys`, then `wezterm cli spawn -- tmux attach`.

Typed rather than passed as the pane's command, so the tab is an ordinary shell
afterwards: leaving `myssh` drops to a prompt, and the line is in history to run
again. Both values go through `printf %q`, so a session name with a space arrives
as one word.

Tabs open in session-creation order (oldest first), in the window the script was
run from, and focus returns to the pane it was run from. That pane comes from
`wezterm cli list-clients`, never `$WEZTERM_PANE` or `cli list`'s `is_active`.
See [tmux-restore-tabs.md](tmux-restore-tabs.md) for why both of those are wrong.

A failed `tmux new-session` stops the script. The check is not optional:
`send-keys -t ''` does not fail, it types into whatever pane tmux considers
current (measured), which would run `myssh` in someone else's pane.

## Known limit

A connection that is still **live** under a conn_id equal to an adopted
session's name has its record overwritten. That needs a live connection whose
own `local-<n>` session is detached while it sits in another one, and it costs
that connection its tracking on the next reconnect — the same fallback-to-conn_id
behaviour `attach` already has.

## Testing (`tmux-restore-ssh-tabs.test.sh`)

Docker only (`bin/test-in-docker`). A real local tmux (own `TMUX_TMPDIR`) whose panes run `cat`, so the line the
script typed is echoed back and can be run through zsh the way the pane's shell
would — the assertion is on which session and host `myssh` would receive, not on
the text. `ssh` and `wezterm` are stubs: the remote half is pinned by
`tmux-track-session.test.sh`, and WezTerm cannot run on a CI runner.

The failure cases matter as much as the happy path: a failed `adopt` and an empty
one must both exit non-zero and open nothing.
