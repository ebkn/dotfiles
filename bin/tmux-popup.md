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
for it here.

## Where `p` and `t` open: `@popup_dir`

`-d` for `p` and `t` is `#{E:@popup_dir}`, set once in `.tmux.conf`: the
Claude session's own cwd (`@claude_cwd`) when the pane runs one, the pane's
`#{pane_current_path}` otherwise. That path is the claude process's directory,
and a Bash-tool `cd` (`gw`) never moves it, so the popups opened in the checkout
a session had already left for a worktree.
[session-cwd.sh](../root/.claude/hooks/session-cwd.md) publishes `@claude_cwd`
on SessionStart/CwdChanged and unsets it on SessionEnd. `o` still uses the pane
path.

**The `p` shell popup keeps the directory it was created in.** `new-session -A`
attaches to an existing `_popup_<id>` and ignores `-c`, so a scratch shell left
open in that tab stays where it was. That was already true when the pane itself
moved; `t` exits with tig, so it always starts fresh.

`tmux-conf.test.sh` evaluates `@popup_dir` against a pane with and without the
option, a path containing a comma included (the conditional splits on commas
before expanding its branches, so the value is safe), and checks both bindings
ask it.

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

Tested in `tmux-popup.test.sh`, with tig stubbed. The failing path runs in a
pane of a throwaway server (`remain-on-exit on`) because the pause reads one key
from a real terminal, so it cannot be checked by piping:

- a failing tig leaves its own message **plus** the pause line on screen, the
  pane is still alive half a second later, and `send-keys x` (one key, no Enter)
  closes it with tig's exit status;
- a succeeding tig exits 0 at once with no pause, and its arguments reach tig.

Asserting on exit status alone proves nothing — the bug this fixes was a popup
that vanished, not one that errored.

## fzf-nvim

`bin/fzf-nvim` is the `prefix + o` command, tested in the same suite with fzf and
nvim stubbed: the pick is opened after `--` (a file named like an option is still
a file), the preview reads the last tab-separated field, and cancelling still
opens nvim — the popup closes the moment its command exits.
