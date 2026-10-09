# zsh/ssh.zsh — the ssh wrappers

`ssh()` decorates the pane and publishes `@ssh_host`; `myssh()` adds autossh
reconnection (see [bin/autossh-ssh.md](../bin/autossh-ssh.md)) and a Wi-Fi
keepalive.

## ssh-parse-argv.test.zsh

Pins `_ssh_parse_argv`, the argv walk that decides which element of an `ssh`
command line is the host. **Everything downstream trusts that answer**: `ssh()`
publishes it as `@ssh_host` (pane colour, status bar, and the host set
`bin/tmux-agents` queries over ssh), and `myssh()` hands it to autossh as the
connection target — so a misread host reconnects somewhere else rather than
merely looking wrong.

**The one part that rots is the character class of ssh(1) options taking a
separate argument.** It is hand-copied from the manual, and an openssh release
adding one makes the parse read that option's value as the host, silently. `-B`
and `-P` were missing for exactly that reason.

Keep the class in the manual's order so it stays diffable against `man ssh`.

The test sources `zsh/ssh.zsh` whole, deliberately — a pasted copy of the
function would not catch the module breaking.

## ssh-decorate.test.zsh

Pins `_ssh_decorate_on` / `_ssh_decorate_off`, the pair `ssh()` and `myssh()`
share to mark the pane while a connection is open.

**The failure worth catching is asymmetry** — something set on the way in and not
cleared on the way out — because both halves of that are silent: a pane still
carrying `@ssh_host` stays purple and keeps claiming a host that is gone, and one
still carrying `@ssh_my_machine` swallows `prefix + p` forever, forwarding it to a
remote tmux that is not there.

One assertion states that directly, by diffing the options `_on` sets against the
ones `_off` unsets.

`_off` clears `@ssh_my_machine` even on the plain `ssh` path that never sets it:
unsetting an unset user option is a silent no-op (verified), and clearing both is
what keeps the pair exact inverses.

The wrappers themselves can only be checked for pass-through here — with stdout a
pipe they set `decorate=false` and skip the pane work by design, so a test that
captures output cannot reach it through them.

## ssh-keepalive.test.zsh

Pins the lifetime **and the count** of the Wi-Fi keepalive ping `myssh` runs:
one ping per host, for as long as any connection to that host is open.

The ping **has** to be disowned (`&!`) or it would print `[1] 12345` on every
connection and `terminated` on every disconnect — but a disowned job also
outlives the SIGHUP a shell sends its jobs on the way out, and `myssh`'s own
cleanup is only reached when `myssh` *returns*. **Closing the pane mid-session
therefore left a ping running at three packets a second until the machine was
rebooted**, with nothing left anywhere that would stop it.

`_ssh_keepalive_start` disowns a **supervisor** instead: the ping is its child,
it wakes every `_SSH_KEEPALIVE_POLL` seconds to check that some shell which asked
for the keepalive is still there, and a `trap` covers it being killed.

**One per host, because one per connection was measured as the bulk of the
traffic.** With a `myssh` per tab, four tabs on one host ran four pings — ~27
packets a second, more bytes per hour than all four terminals together. The
radio and the NAT mapping are per host, so the extra three kept nothing warmer.
Connections live in separate shells, so they share through
`$_SSH_KEEPALIVE_DIR` (per user under `$TMPDIR`): each shell registers an owner
file named by its pid, and a supervisor pings only while it holds the host's
lock — a symlink whose target is its pid, so `ln -s` is the atomic step and a
holder killed outright is recognisable as stale. `_ssh_keepalive_stop` only
unregisters; the supervisor stops the ping at its next poll once no owner is
left alive.

**The contract is a lifetime and a count, not an output**, so the test watches
**real processes** — only `ping` is stubbed (nothing may put packets on the wire
from a test); the disowned supervisor, the lock, the poll loop and the signals
are the real thing.

Three seams make that fast and isolated rather than a pile of sleeps:
`_SSH_KEEPALIVE_POLL` is turned down to 0.2s, `_SSH_KEEPALIVE_DIR` points at a
scratch dir so a test never joins a live session's ping, and
`_ssh_keepalive_start` takes the owner pid as an optional second argument so one
test can play several shells and own processes it is allowed to kill.
Disappearance and the expected count are polled for (`wait_gone`,
`settled_pings`), so a slow start is waited out rather than miscounted; only "no
extra ping appeared" is a fixed wait, because absence cannot be polled for.

The `ping` stub records the host it was asked for as well as its pid. One that
accepted any argv stayed green with the target dropped, while the real `ping`
exits at once on a usage error — the keepalive gone, silently.

Shapes checked by breaking it and confirming red:

1. the original bare `ping … &!` (the shell-dies case fails);
2. a supervisor with no `trap` — killing it **orphans the ping**. `stop` no
   longer signals the supervisor, so this is reached only by a kill from
   outside, and has a case of its own;
3. a supervisor that never checks its owner;
4. no lock — every connection pings (the two-sessions case fails);
5. no stale detection — a SIGKILLed supervisor blocks the host forever;
6. `ping` run without the target;
7. an unguarded `mkdir` of the state dir, which prints on every connection when
   the dir cannot be created (that case needs a non-root runner).

**The state lives in `$TMPDIR`, which macOS sweeps.** `com.apple.bsd.dirhelper`
runs daily at 03:35 with `CLEAN_FILES_OLDER_THAN_DAYS=3`, and connections here
have run for six days. An owner file swept from under a live connection reads as
"nobody left" and stops its ping, so the supervisor `touch`es the live owner files
and its lock every poll. The sweep case emulates dirhelper with `find -mtime +3
-delete`; whether dirhelper judges by mtime or atime was not checked, and `touch`
refreshes both.

**Not covered: the supervisor's second look.** A supervisor that finds no owner
drops the lock and scans once more, for a shell that registered in between and
left the ping to it. Removing that second scan stays green, because the window is
a few milliseconds and the test has no hook to land a registration inside it.

The test kills every pid its stub recorded on the way out, because a failing run
is by definition one that leaked a process.

## ssh-session.test.zsh

Pins which remote session `myssh` attaches to: `local-<pane id>` by default,
`$MYSSH_SESSION` when set (by `bin/tmux-restore-ssh-tabs`).

The remote command is **run through `sh`** against a stub `tmux-track-session`,
exactly as the remote login shell would, rather than matched as text — a name with
a space passes a text match and is then split in two by the remote shell. That is
why the name is quoted with `${(q)…}` before it goes into the command.
