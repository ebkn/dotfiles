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
`ssh::decorate_off` sends on the way out, sent here on the way **in**.

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
   it clear, and only the first notice of each outage clears, so a retry a
   second does not flicker. The counter lives as long as myssh, so a connection
   that came back and dropped again starts its outage at attempt 3 or later;
   that first notice is recognised by the previous attempt having run 30s or
   more (the state file holds `<count> <start epoch>`). The shim execs ssh and
   never learns whether an attempt connected, so duration is the stand-in. It
   errs both ways: a slow failure or a long backoff costs one extra clear, and
   a session that drops within 30s of connecting is taken for a failed attempt,
   so its frame and mouse modes stay up for that outage.
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

**The outage cases run on a stubbed clock** (`date` on `PATH`, answering
`FAKE_NOW`), attempt after attempt with no re-seeding between them. They first
seeded `<count> <epoch>` by hand before each attempt, which passed with a shim
that never wrote an epoch at all — myssh's own case, since its state file
starts empty — so what is pinned now is the shim's write and its read-back.

The notice is drawn on **`AUTOSSH_NOTICE_TTY`** (default `/dev/tty`; only the
test sets it), pointed at a plain file so the frame is read back whole. The suite
used to read the notice off the shim's stderr instead, which only works with no
controlling terminal: run from an interactive shell it failed five cases and left
that terminal cleared with its cursor hidden. A plain file has no size, so the
shim falls back to 24x80 and the columns are fixed. The stderr fallback is still
tested, by pointing the variable at a path that cannot be opened.

Each attempt is checked on argv (the reconnect is the attempt that matters most),
on the whole visible text rather than a substring — a stray "Device not
configured" in front of the notice is the mess this exists to remove — with a
different ssh message per attempt, so "the previous attempt's message" cannot be
satisfied by the current one, and on **stdout carrying ssh's output alone**,
since stdout is the session: a notice written to stdout would otherwise pass.

It caught the `/dev/tty` trap [read-doc](read-doc.md) documents on its first run:
`stty size </dev/tty 2>/dev/null` does **not** suppress "Device not configured",
because the message comes from the redirection rather than from `stty`, and it
landed in the middle of the notice.

**The cases that earn their keep are the ones where doing nothing is the correct
behaviour**: attempt 1 draws nothing at all and passes argv through untouched, a
later attempt does not re-clear the screen, and ssh's exit status passes through
unchanged — since that number *is* autossh's restart policy.
