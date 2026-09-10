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

Pins the lifetime of the Wi-Fi keepalive ping `myssh` runs.

The ping **has** to be disowned (`&!`) or it would print `[1] 12345` on every
connection and `terminated` on every disconnect — but a disowned job also
outlives the SIGHUP a shell sends its jobs on the way out, and `myssh`'s own
`kill` is only reached when `myssh` *returns*. **Closing the pane mid-session
therefore left a ping running at three packets a second until the machine was
rebooted**, with nothing left anywhere that would stop it.

`_ssh_keepalive_start` now disowns a **supervisor** instead: the ping is its
child, it wakes every `_SSH_KEEPALIVE_POLL` seconds to check the shell that asked
for the keepalive is still there, and a `trap` covers the ordinary path where
`myssh` kills it.

**The contract is a lifetime, not an output**, so the test watches **real
processes** — only `ping` is stubbed (nothing may put packets on the wire from a
test); the disowned supervisor, the poll loop and the signals are the real thing.

Two seams make that fast and non-flaky rather than a pile of sleeps:
`_SSH_KEEPALIVE_POLL` is turned down to 0.2s, and `_ssh_keepalive_start` takes the
owner pid as an optional second argument so a test can own a process it is
allowed to kill. Assertions poll for the answer (`wait_gone`), so a pass is
immediate and only a genuine failure pays the timeout.

Three shapes were checked by breaking it and confirming red:

1. the original bare `ping … &!` (the shell-dies case fails);
2. a supervisor with no `trap` (`stop` kills the supervisor and **orphans the
   ping**);
3. a supervisor that never checks its owner.

The test kills every pid its stub recorded on the way out, because a failing run
is by definition one that leaked a process.
