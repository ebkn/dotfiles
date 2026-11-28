# tmux-open-github

`prefix + g` opens the pane directory's PR on GitHub, or the repository when
the branch has none, in the browser **of the machine the terminal runs on**.

`tmux-open-github <pane_tty> <dir>` is what the binding runs, through
`run-shell -b`. It asks `gh pr view --json url`, then `gh repo view --json url`,
and says with `display-message` which URL it opened, or why it did not: `<dir>`
is no GitHub repository, cannot be entered, the opener failed, or (over ssh)
the pane's tty cannot be written. It always exits 0, since `run-shell -b`
shows nobody a status.

## Over ssh the URL travels back to WezTerm

In a `myssh` pane (`@ssh_my_machine`) the local tmux does not handle the chord:
the repository is the remote's, and the local pane's directory is just where
`myssh` was typed. So the binding sends `C-q g` on to the remote tmux, as
`p`/`t`/`o` already were, and the remote runs this script. Before that, the
chord ran `gh … --web` locally, in a directory that is no repo, and its output
went to `/dev/null`, so nothing opened and nothing said why.

On the remote, `gh --web` or `open(1)` would start a browser where nobody is
looking. With `$SSH_CONNECTION` set, the script writes the URL as
`OSC 1337 SetUserVar=open_url=<base64>` instead, and the `open_url` arm of
`user-var-changed` in `wezterm.lua` opens it with `wezterm.open_with`. This
is the channel `read-doc` uses (see [read-doc.md](read-doc.md#forward-mode-reading-a-document-from-inside-an-ssh-session)),
with the same two details:

- **Depths 0, 1 and 2 are all sent**, because each tmux on the way strips one
  passthrough wrapper and the remote cannot count them. Needs
  `allow-passthrough on` on both tmuxes, which `.tmux.conf` sets.
- **The base64 is unwrapped** (`tr -d '\n'`): GNU base64 breaks its output at
  76 columns, and a newline would end the OSC early. A PR URL is easily past
  the 57 bytes where that starts.

It is written to `<pane_tty>`, not `/dev/tty`: `run-shell` has no terminal,
and output written to the pane's tty is read by the remote tmux as the pane's
own, so it passes through like any program's.

**Trust boundary:** anything that can write to a pane can set `open_url`, so
`wezterm.lua` opens only an `https://github.com/` URL without whitespace or
control characters, and logs anything else.

**`$SSH_CONNECTION` is the session's, so it follows the client that attached
last, not the one that pressed the key.** `run-shell` inherits the session
environment, and `update-environment` (default list, which includes
`SSH_CONNECTION`) sets it from each attaching client, removing it when that
client has none (tmux(1)). One client at a time is always right. With two
attached at once, an ssh one and one at the remote's console, a press from
the earlier one is routed as if made from the later: the URL goes to the pane
from the console, or a browser opens on the remote for the ssh client.

## The directory is an argument, not `run-shell -c`

`run-shell -c` takes its directory as written: `-c "#{pane_current_path}"` is
not expanded, so the script ran in `$HOME`. `#{q:pane_current_path}` in the
command itself is expanded and shell-quoted. `bin/tmux-conf.test.sh` presses
the chord through a real client and checks both arguments, which a check on the
binding text could not show.

## Testing

`bin/tmux-open-github.test.sh` stubs `gh`, `tmux`, `open` and `xdg-open` on
`PATH`. It checks which URL is chosen, that `gh` runs in `<dir>`, that a
directory with no repository, a directory that is gone and an unwritable tty
each say so, and that over ssh nothing opens remotely and the pane receives
exactly the depth 0, 1 and 2 sequences for a URL long enough to wrap. Exactly,
because depth 0 is a substring of depth 1 and a "contains" check could not
show it was sent. It sources the tmux guard only because every `bin/tmux-*.test.sh` must.
The WezTerm handler has no test: nothing here runs `wezterm.lua`.
