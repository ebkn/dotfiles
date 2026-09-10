# tmux-session-swap

Swap two clients on `prefix + w`, so one WezTerm tab keeps meaning one tmux
session.

## The invariant nothing in tmux enforces

**One WezTerm tab means one tmux session.** tmux's own `w` is
`choose-tree -Zw`, whose Enter runs a plain `switch-client`: it will put a second
client on a session another client already shows, and the two tabs then mirror
each other — same window, same cursor, one tab's keystrokes moving the other's
pane — while the session the picker came *from* is left with no client at all.

Picking an "unattached" session, the one case that looks safe, is precisely the
one that creates the next orphan.

So `w` **swaps**: the client holding the chosen session is moved to the session
being vacated, and only then is the picker moved to its choice.

## Why it is two commands (`arm` then `go`)

Neither half can be done alone:

- choose-tree's command template substitutes `%%` but cannot name the *picking*
  client;
- `set -g @x "#{client_tty}"` stores the string literally — **`set-option` does
  not expand formats**, which is the same reason `@claude_glyph` is pre-computed
  by a hook (see
  [agent-state.md](../root/.claude/hooks/agent-state.md)).

`run-shell` **does** expand formats, against the client that pressed the key, so
the tty is captured in the binding body and parked in a file for the `go` step.

The window between `arm` and `go` is one keystroke wide; two clients opening the
chooser inside it would have the second overwrite the first, costing a wrong swap
and nothing worse.

**`go` reads and clears the arm before anything else**, above even resolving the
target: the file means "a chooser is open right now", so an early return that
skipped the removal left a tty on disk describing a chooser that had closed. The
binding papers over that by re-arming every time, which is exactly why it went
unnoticed.

## The binding survives tmux's parser

That the `\"%%\"` nesting comes through intact is no longer a hand-check on tmux
3.7b — `bin/tmux-conf.test.sh` asserts the `list-keys` readback, because losing
either half is silent: without the arm, `go` degrades to the plain switch this
exists to replace; without the escaping, `w` does nothing at all. The config
loads without an error either way.

## Testing (`tmux-session-swap.test.sh`)

Runs against a real throwaway server with **real attached clients**, because what
it pins is the client-to-session mapping tmux is left holding. A stub could only
check the command line the script decided, and the readings that drive the
decisions (`session_attached`, `list-sessions -f`) are exactly what a stub would
freeze.

Four things make that possible, and each was a failed run first — shared with
[tmux-track-session](tmux-track-session.md), see that file for the full list:
`TMUX` must be unset; isolation is `TMUX_TMPDIR`, not `-L`; the pty comes from
`script(1)`, probed rather than branched on platform; and `default-command` must
be `sleep`, not the login shell.

Confirmed red against a plain `switch-client`: four failures, including a session
holding two clients.

**Four lessons, each of which was a green test proving nothing:**

1. **Asserting on `$?` is worthless where the script ends in an unconditional
   `exit 0`** — the unarmed fallback did, so replacing that whole branch with `:`
   left the suite green. The assertion is now on the target session gaining a
   client, and *which* client moves is deliberately not asserted, because with no
   recorded tty that is tmux's choice (measured: the most recently attached one).
2. **`tmux display-message -p -t "=<session>" '#{session_attached}'` prints an
   empty string, not `0`**, when nothing is attached — a session format is
   expanded against a client — so it compares equal to another empty reading. Use
   `list-sessions -f`.
3. The `clients_on` loop needs a case with **two** incumbents, since one is also
   handled by the wrong implementation that moves only the first (verified with
   `head -1`). What it promises is about the *chosen* session — the picker lands
   there alone — not about curing the doubling, which simply moves to the vacated
   session.
