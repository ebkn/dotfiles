# autossh-ssh

The reconnect screen. Pointed at by `AUTOSSH_PATH` from `myssh` (`zsh/ssh.zsh`).

## What it fixes

When the link drops, the terminal still holds the remote tmux's last frame, and
two different things scribble on it:

1. ssh's diagnostic per attempt (autossh retries about once a second);
2. if the pointer moves, a flood of raw SGR reports — because the remote tmux
   enabled mouse tracking and nothing is consuming it any more.

**The mouse half is the part worth knowing**, since it looks like a wholly
separate bug and is not ssh output at all. The cure is the same escape sequence
`_ssh_decorate_off` sends on the way out, sent here on the way **in**.

## Why a shim and not a reimplementation

`AUTOSSH_PATH` is the whole reason. A "reconnecting" display needs a hook that
runs once per attempt, autossh offers exactly one, and taking it leaves autossh's
restart policy, backoff and exit handling untouched.

## Three constraints

1. **It must not be named `ssh`.** It resolves the real binary with
   `command -v ssh` and would otherwise find itself.
2. **The first attempt is a bare `exec ssh`.** That one is the initial connect,
   where ssh's own output (host key prompt, "Permission denied") is the useful
   thing on screen and there is nothing stale to cover. Only from the second does
   it clear, and only that one clears, so a retry a second does not flicker.
3. **ssh's stderr goes to a log rather than /dev/null, so the notice can quote
   its last line.** A changed host key retries forever otherwise, behind a line
   that cheerfully says "reconnecting" with the explanation nowhere.

The env is passed with `local -x` and not a command prefix, because
`${var:+FOO=bar} autossh` does not assign — prefixes are recognised when the line
is parsed, so one produced by an expansion arrives as an ordinary argument.

## Testing (`autossh-ssh.test.sh`)

Stubs `ssh` — nothing here may dial out — and the stub records the argv it was
handed, which is the shim's real contract with autossh: drop an argument and the
reconnect itself breaks, on a path that only runs once the network has already
gone wrong.

The notice is read off the shim's **own stderr**, which works because with no
controlling terminal the `/dev/tty` write fails and falls back to stderr, while
ssh's stderr is going to the log from attempt two onwards — so stderr carries the
notice alone.

It caught the `/dev/tty` trap [read-doc](read-doc.md) documents on its first run:
`stty size </dev/tty 2>/dev/null` does **not** suppress "Device not configured",
because the message comes from the redirection rather than from `stty`, and it
landed in the middle of the notice.

**The cases that earn their keep are the ones where doing nothing is the correct
behaviour**: attempt 1 draws nothing at all and passes argv through untouched, a
later attempt does not re-clear the screen, and ssh's exit status passes through
unchanged — since that number *is* autossh's restart policy.
