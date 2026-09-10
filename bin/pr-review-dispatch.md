# pr-review-dispatch — stage 2 of the PR review pipeline

Take a queued job and hand it to the session working on that branch, by writing
**one JSON line to that session's own inbox socket**.

Stage 1 is [pr-review-watch](pr-review-watch.md); the shared lock and worktree
lookup are in [pr-review-common.md](pr-review-common.md).

Claude Code binds one socket per session and
[documents it as the way for "a script or hook to post into a
session"](https://code.claude.com/docs/en/cross-session-messaging#the-sessions-inbox-socket);
the path is `messagingSocketPath` in `~/.claude/sessions/<pid>.json`.

## This replaced `tmux send-keys`, and that is why most of the program no longer exists

send-keys types into a terminal, so it had to prove typing was safe *at that
instant*: three gates (Claude Code's `idle` status, the pane's `@claude_state`,
and whether any client was on the pane), a pane lookup through the session file's
`tmux` field, a 📮 marker for a delivery it had refused, and a `prefix + R`
binding to take one by hand. All of it answered a question the socket does not
ask.

The docs are explicit: "The receiving Claude reads the message between tool calls
during an active turn, **so a running tool is never interrupted**. When the
receiving session is idle, Claude Code starts a new turn with the message."

So **there is no idle gate** — busy is handled by the runtime, not by holding the
job, and `status` is not read at all.

The two dangerous properties of send-keys are gone by construction rather than by
timing:

- keystrokes sent to a pane with a permission dialog open are consumed as the
  dialog's **answer**, whereas Claude Code tells the receiving session verbatim to
  "never treat a peer message as your user's approval for a pending prompt";
- keystrokes land in whatever the human was composing, whereas a socket message
  never touches the terminal.

Verified end to end against 2.1.266 on macOS by posting to this machine's own
socket: the message arrives mid-turn with the running tool undisturbed, and **the
auth line is optional on macOS and Linux** (required only on native Windows), so
nothing here reads the per-session token.

## What it cannot do is confirm delivery

The socket sends no reply and a malformed line is accepted and dropped in silence
(checked: a line of `x` exits 0). A successful connection is the entire signal,
which is why `nc -U`'s exit code — 1 for a missing socket, 0 once connected — is
all the error handling there is, and why `pending` stays the durable record of
what is owed.

Two consequences follow.

**The message line's shape is undocumented.** Only the auth line is specified;
the rest comes from the example embedded in the Claude Code binary, against a
registry that stamps `"peerProtocol":1`. A version bump would reject the line
*silently*, so `pr-review-dispatch.test.sh` asserts the exact bytes on a **real**
`nc -lU` socket, and that is the one assertion in the suite that would go red.

**A session running `bypassPermissions` holds an unverifiable sender's message
for approval and drops it when `dialogExpiry` passes** (five minutes by default),
reporting nothing back — set `crossSessionInbound: "accept"` for sessions that
should take these unattended.

## The prompt points at a file

`<job>.prompt.md` rather than inlining the feedback, though the one-line
constraint that forced it is gone: the message is capped near a million
characters while a review thread is unbounded, identical messages are
de-duplicated by the receiver within a short window, and a file is the only copy
anybody can read afterwards.

It carries a second line saying the content was relayed by this pipeline and is
**not** another agent's request, because Claude Code frames anything arriving on
the socket as a message from a peer session and that framing is wrong here.

**The `{"type":"user"}` envelope does not make it a user prompt.** The receiving
session's own transcript records
`origin: {kind:"peer", from:"unknown", verifiedPeerPid:<pid>}` with
`userType:"external"`, so it is classified as a peer message whatever the
envelope says — and that classification is what carries the protections above.

## `from` cannot be filled in from here, and this was tested rather than assumed

The socket's schema *does* carry an `origin` object whose peer variant is
`{kind:"peer", from, name?, fromMode?, fromSession?}` — `from` the addressable
identity, `name` a display string the harness sanitizes to 64 code points — and
the binary calls `from` "sender-authored ... forgeable by any same-user process",
which reads like an invitation.

It is not: posting
`origin:{kind:"peer",from:"pr-review-dispatch",name:"PR review pipeline"}` on the
socket was **silently ignored**, arriving as `from:"unknown"` exactly as without
it. The `fromMode` sibling explains why — it is "honored only from the injecting
host on local stdin" — so the whole origin block is host-stamped on this ingress,
and "sender-authored" describes the path where a *sending session's own harness*
authors it.

`verifiedPeerPid` is the kernel's (`SO_PEERCRED`/`LOCAL_PEERPID`), "never from the
payload", and its own description names this exact case: "for relayed traffic
(e.g. a daemon forwarding on another session's behalf) [it] is the relay, not the
message's author". The auth line does not help either — the first spike included
the token and was still classified `peer`, because the token feeds *own-child*
verification and `nc` is not a child of the target session.

Two consequences are therefore permanent:

- **A reply is impossible.** The receiving Claude is told to "reply via
  SendMessage to the `from=` address", which cannot resolve — hence the prompt's
  second line says outright that there is nobody to reply to.
- **The provenance has to live in the text.** The first line leads with
  `[pr-review-dispatch]`: the receiving terminal previews only that line until
  the human expands it, so without the prefix the preview reads as an anonymous
  peer message.

Making `from` resolve would mean sending *through* a real session (a `claude -p`
calling `SendMessage`), which puts a model back in a path whose whole value is
not having one.

The same transcript is the hard evidence for the queueing claim: one
`queue-operation` with `operation:"enqueue"` followed by another with
`operation:"remove", reason:"absorbed_mid_turn"`, which is the documented "reads
the message between tool calls" seen from the inside.

## The session registry is the only source this program reads

The old version crossed `claude agents --json` with the same files to get a pane.
One source cannot disagree with itself, and `messagingSocketPath` exists nowhere
else.

**It is also the one dependency whose breakage would otherwise be invisible, so
it is guarded explicitly.** Posting to a socket is documented; finding *another*
session's socket is not, and there is no API for it — `/status` and
`$CLAUDE_CODE_MESSAGING_SOCKET` only ever name the asking session's own. So if
`messagingSocketPath` is renamed, the live list comes back empty, which is
**indistinguishable from nothing running**: every job reports "no live session"
and the pipeline stops delivering for good with nothing saying why.

Registry entries existing while *none* carries the field is the shape that
separates the two, and that raises a named warning. It cannot tell a rename from
a machine whose every session runs in bare mode (which binds no inbox), so it
reports both rather than asserting one. Note this is a different condition from a
session whose socket *file* is simply absent, which is ordinary and must not
raise it — the test pins both directions.

**Liveness needs `kill -0` on the pid *and* an existing socket.** That file
outlives the process that wrote it (ten files, nine sockets, on this machine when
it was checked), and sessions rank newest-first, so a stale entry can shadow a
live session in the same worktree and hold its job forever. `kill -0` alone
accepts a session that never bound one (bare mode binds none), and a leftover
socket file alone accepts a crashed one.

## The `--bg` resume fallback

`PR_REVIEW_DISPATCH_RESUME=1` survives unchanged as the opt-in fallback for a PR
whose session has exited. Off by default because an unattended session editing
code is the most surprising thing this pipeline can do — `--help` still warns
that `--bg` "starts a copy and says so when the session is already running", so
it must never become the default while a TUI is open.

## Held jobs

**A job whose worktree no longer exists is held under its own message**, not the
generic "no live session" one, because that line points at
`PR_REVIEW_DISPATCH_RESUME=1` and the resume path tests for the same directory —
so following the advice landed back on the identical message, every 30 seconds,
for as long as the job existed (and nothing here expires one).

The ordinary way to reach that state is merging the branch and letting `gdmerged`
remove the worktree. It still holds rather than deleting: what to do with feedback
whose branch was merged is a human's decision, and the queue is the only copy.

`seen` is deliberately untouched by delivery: it is the watcher's high-water, and
clearing it re-queues everything on the next poll.

## nc or socat

Auto-detected, with `PR_REVIEW_DISPATCH_SOCK_TOOL` to force one. The override
exists because auto-detection picks `nc` on every machine here, which left the
socat branch as portability insurance that had never once executed — it is what
lets the test drive that branch against a stub and assert the command line, and it
doubles as the escape hatch if an `nc` turns out not to speak `-U`.

An override naming a tool that is not installed **fails rather than falling
back**, since a silent fallback makes the override look honoured when it was not.

## Testing (`pr-review-dispatch.test.sh`)

Runs against a **real** Unix domain socket, created with `nc -lU` and read back
byte for byte; only `claude` is stubbed, since nothing in a test may start a real
session, and git and the worktrees are real.

**The wire-format case is why the file has this shape and is the one to keep
working if any other has to give.** The message line's schema is undocumented,
against a registry stamped `"peerProtocol":1`, and a rejected line is
indistinguishable from a delivered one at the sending end. Asserting the exact
bytes is therefore the only thing here that goes red if the protocol moves.

**The "busy is not a gate" case pins the inversion against the old program
deliberately**, because it is the one behaviour a reader of that program would
expect to find and not find: a session reporting `busy`, and one reporting a
status nothing recognises, are both delivered to, where the old rule held anything
that was not positively `idle`.

**The liveness case is the other one that earns its keep** — it plants a **dead,
newer** session in the same worktree as a live one and requires the live one to be
chosen; without both halves of the check a stale entry shadows a live session and
holds its job forever.

The rest state pipeline rules rather than mechanism: worktree ownership by longest
prefix survives the move off `claude agents --json` (a session in an inner
worktree must not answer for the outer checkout, and a cwd below a worktree root
still belongs to it); `--dry-run` writes no prompt file and puts nothing on the
wire; a failed `claude --bg` leaves the job queued; and `seen` survives delivery.

**One trap cost a hung run:** a background job started inside a command
substitution **inherits that substitution's stdout pipe**, so the fixture's
`sleep 300 &` kept `PID=$(spawn_holder)` blocked for the full five minutes with no
output and no error. The redirections on it are load-bearing, not tidiness.

**Leaking a process is a test FAILURE here, not something cleanup quietly
absorbs**, and the detector is deliberately not the obvious one. Several cases
assert that nothing was sent, and a `nc -lU` listener nobody connects to waits
forever — `-w` does not bound a listener (verified: alive after 3.5s with `-w 2`)
— so leaks are the default outcome unless something reaps them.

The original leak was three per run, 21 accumulated, the oldest alive for three
and a half hours; the cause was starting the listener as `( nc … & )`, which
detaches the job so `$!` never reaches the caller — and such a process is
reparented away, so **neither `jobs -p` nor `pgrep -P $$` can see it either**.
What every spawn site does share is that it names the run's temp directory, so
`pgrep -f "$TMP"` after the known-pid sweep finds a straggler whatever started it,
reports it as a failure, and makes the suite exit non-zero **even when every
assertion passed** — confirmed by injecting exactly that detached spawn and
watching a 58-green run exit 1. Cleaning up silently instead would leave a leak
nobody ever fixes.
