# tmux-track-session

Remember the remote session an ssh pane was in, so an autossh reconnect lands
back in it.

## The binding must be single-valued in both directions

One conn_id names one session, *and* one session is named by at most one conn_id.

Only the first half was enforced, and `prefix + w` on the remote is what broke
the second: the monitor recorded the newly chosen session under this conn_id
while the conn_id that was already there kept its own record, so the **next
autossh reconnect resolved both to the same session** and tmux mirrored two
WezTerm tabs onto it.

Found live as `local-5023 attached=2` with `local-2` and `local-259` both
pointing at it, plus a displaced chain (`local-925 → local-175`,
`local-254 → local-925`).

The monitor now *releases* a session from every other conn_id when it claims it —
last visitor wins, and the released connection falls back to its own
`local-<pane>` session, which is where it would have been had it never switched.
`attach` refuses to join a session that already has a client instead of mirroring
it.

## Pruning dead records

Records naming a dead session are pruned on attach. They were already inert, but
177 of them had accumulated against 10 live sessions, and **a tmux pane id is
only unique within one server lifetime**, so a record outliving its server can be
handed to a new connection that reuses the id.

The pruning reads `list-sessions` **twice total**, not `has-session` per record —
this runs on every reconnect, and 177 × ~5ms is most of a second of reconnect
latency.

Both `case` patterns are newline-delimited on *both* sides, or `local-5` would
match `local-50`.

## Lifecycle

**`attach` starts the monitor through `$0`, not a hardcoded
`$HOME/.local/bin/tmux-track-session`** — the copy that is running is the copy
that should keep running. Hardcoding it meant a change tested in a git worktree
ran the *main* checkout's monitor (the trap `.zshrc` documents for `$0`), and on
a machine where `relink` has never run — a CI runner — the path does not exist
and the monitor simply never starts, which says nothing because `attach` still
lands in the right session.

The path must stay absolute: `run-shell` executes with tmux's environment, not
the calling shell's.

**The stale pid is identified before it is signalled**, by matching the owning
process's argv (script name, `monitor`, this conn_id). A monitor killed without
running its trap leaves its pid file behind and the OS may hand that number to
anything, so the blind `kill` this replaced landed on a bystander, on a remote,
silently. `bin/pr-review-common.sh` settles for `kill -0` because a recycled pid
there only costs a missed steal; here the mistake is destructive, so liveness is
the wrong question.

`ps` needs **`-ww`**, or procps truncates to the terminal width, the conn_id falls
off the end of an absolute path, the match never succeeds on Linux, and every
reconnect leaks a monitor instead.

## The monitor must never die by a signal

tmux reports a `run-shell` job that exits non-zero or is signalled as
`'<cmd>' terminated by signal 15` and opens that report in a **view mode covering
the pane** — and the pane here is the *remote* screen of an ssh session, so the
report landed on top of whatever was drawn there and had to be dismissed by hand.

`attach` TERMs the previous connection's monitor on every reconnect, so it fired
every time the link came back. That is the whole "the remote screen gets dirty on
reconnect" symptom.

A `trap … exit 0` is the fix; tmux says nothing about a job that exits 0 silently.

## Testing (`tmux-track-session.test.sh`)

Runs against a real throwaway server with **real attached clients**, because what
it pins is the client-to-session mapping tmux is left holding — a stub could only
check the command line the script decided, and the readings that drive the
decisions (`session_attached`, `list-sessions -f`) are exactly what a stub would
freeze.

Four things make that possible, and each was a failed run first:

1. **`TMUX` must be unset.** tmux refuses a nested attach, so inside a tmux pane
   every client silently fails to appear and `list-clients` comes back empty with
   no error.
2. **Isolation is `TMUX_TMPDIR`, not `-L`** — this script calls bare `tmux`, so
   with `-L` its queries land on the developer's own server, and its `attach` ends
   in `new-session -A`, which would create a session there.
3. A pty comes from `script(1)`, whose command line differs between BSD
   (`script -q <file> <cmd...>`) and util-linux (`script -qec "<cmd>" <file>`).
   The helper **probes** rather than branching on the platform, since macOS can
   have either.
4. Sessions the script creates itself take their pane from `default-command`,
   which must be set to `sleep`. Left as the login shell, `.zshrc` runs and the
   pane is gone before anything can be asserted — the same trap
   `tmux-pane-titles.test.sh` documents.

Confirmed red against the monitor without its release step: two conn_ids naming
one session.

**Kill by pid, never `pkill -f`** — the pattern matched a monitor belonging to a
live ssh connection into this machine, or to a second copy of the suite. Poll
rather than sleeping.

`attach` is only reached through the script's own path, so **nothing exercised
the `run-shell -b` that starts the monitor** until a case followed attach through
to the record its monitor writes; confirmed red by pointing `HOME` at an empty
directory, which is the CI condition exactly.

### The second suite

Pins that the monitor never dies by a signal (above). **The harness needs two
tmux servers, not one**, and that is the load-bearing part: tmux hands a job's
output to a *client*, so against a detached server the message is never rendered
and every assertion passes vacuously. The outer server exists only to supply the
pty the inner one attaches through, and the screen is read by capturing the outer
pane.

The first case deliberately signals a throwaway job and asserts the report
**does** appear, so a broken reproduction fails loudly instead of proving
nothing.

Assertions poll `#{pane_in_mode}` rather than sleeping a fixed amount: at half a
second the regression case went green against the unfixed script, because the
monitor is inside `sleep 2` when the signal lands and two servers then have to
render.
