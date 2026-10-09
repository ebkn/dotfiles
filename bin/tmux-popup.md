# tmux-popup

Open a per-tab popup session. `prefix + p` (shell), `prefix + t`
([tig](#tmux-tig)) and `prefix + o` (fzf → nvim, via `bin/fzf-nvim`) all go
through it.

Each opens a **real tmux session on the same server**, displayed in a
`display-popup`. This script owns the two rules all three share — the session is
named `_<name>_<id>`, and it starts in `$PWD` — so the bindings in `.tmux.conf`
carry no shell quoting at all.

They used to build the `tmux new-session` line inline, which cost `\$`/`\"` in
every binding and `\\\$`/`\\\"` in the `o` one, whose fzf command had to survive
one shell further down.

## The name is a contract split across two files

The leading `_` is what `.tmux.conf`'s `@in_popup` (`#{m:_*,#{session_name}}`)
matches; `prefix + p/t/o/a/A/g/?` refuse to open a popup inside a popup by asking it,
and `prefix + d` skips its confirmation there. Renaming the scheme here without
changing that one line makes `prefix + p` stack popups with no error. Both
halves are pinned: `tmux-popup.test.sh` reads the glob from the `@in_popup` line
and matches every name it builds against it, and `tmux-conf.test.sh` evaluates
`@in_popup` against a popup-named and an ordinary session and checks each
guarded binding asks it. `tmux-track-session adopt` and `tmux-restore-tabs` also
skip `_*` sessions as popups — two more readers of the same rule, each pinned by
its own suite but not tied to the `@in_popup` line.

[tmux-agent-view](tmux-agent-view.md) rides the same guard with its
`_agent_<window>_<pid>` mirror sessions.

## Why `<id>` comes from `$TMUX`

The `<id>` is the third comma-separated field of `$TMUX`, the numeric session id,
and makes the popup unique per WezTerm tab — without it every tab attaches to the
same popup session.

It cannot come from a `#{...}` format: **display-popup expands formats only in
`-d`, never in the shell-command**, so `_popup_#{pane_id}` was passed through
verbatim as one shared literal name. ([bin/tmux-agents](tmux-agents.md) derives
its calling client from `$TMUX` for the same reason.)

`-d` has already set the popup shell's directory, which is why `$PWD` stands in
for `#{pane_current_path}`.

## Testing (`tmux-popup.test.sh`)

The one tmux script here checked against a **stubbed** `tmux` rather than a
throwaway server, and the reason is structural: the script's whole job is
`tmux new-session -A`, which *attaches*. Attaching from inside a pane is nested
attach and tmux refuses it, and `run-shell` has no pty at all
(`open terminal failed: not a terminal`) — the real path needs `display-popup`,
which needs an attached client.

So the stub records argv and the assertions are on the command line the script
decides, which is the part it owns. The load-bearing case is that every name it
produces matches the glob in `.tmux.conf`'s `@in_popup` line — read from that
line, not restated — and a mismatch makes `prefix + p` stack popups silently.

**The end-to-end path cannot be automated here** — after changing `tmux-popup`,
press `prefix + p`, then `prefix + p` again inside the popup and expect "already
in a popup".

## tmux-tig

`bin/tmux-tig` runs tig and holds the popup open on failure (`prefix + t`).

**Pinned by `bin/tmux-tig.test.sh`**, with tig stubbed and the script run in a
pty through util-linux `script(1)`, its input a fifo: held open, it shows the
popup still standing before any key; one byte, no Enter, closes it with tig's
status. Container or CI only, through the tmux suites' guard — BSD `script(1)`
refuses a fifo on stdin, and the pause reads `/dev/tty`, which on a developer's
machine is their own terminal.

By hand, against a throwaway tmux server
(`tmux -L <name> -f /dev/null new-session -d -c <dir> tmux-tig`), check both
paths with the real tig:

- in a non-git directory the pane must show tig's own
  `tig: Not a git repository` **plus** the pause line, and must survive until
  `send-keys x` (one key, no Enter) closes it;
- in a repository tig must open as before and `q` must exit with no pause.

Asserting on exit status alone proves nothing — the bug this fixes was a popup
that vanished, not one that errored.
