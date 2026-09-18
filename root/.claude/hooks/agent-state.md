# agent-state.sh — the agent state indicator

Which Claude session is running, and which is blocked — on a question it asked,
on a permission prompt, or simply on nobody having looked — is published as
**tmux pane user options** on the pane the session runs in.

Consumers are `set-titles-string` in `.tmux.conf` and
[bin/tmux-agents](../../../bin/tmux-agents.md).

## Published options

| Option | Meaning |
| --- | --- |
| `@claude_state` | `busy` ▶ / `asking` 🛑 / `waiting` 🛑 / `needs_input` 🛑 / `stalled` 🟢. Unset means idle. |
| `@claude_glyph` | The rendered glyph, stored ready to concatenate. |
| `@claude_since` | Epoch seconds. |
| `@claude_note` | The pending question or permission message. |
| `@claude_agents` | The per-actor listing (see below). |

Pane options rather than state files, because tmux formats read them directly —
that is what lets the tab glyph exist with no `#()` subprocess and lets
`status-interval` stay at 30s. Same storage pattern as `@ssh_host` /
`@git_branch`.

**The separator is baked into `@claude_glyph` per glyph**, since the
emoji-presentation ones already occupy two cells while the narrow `▶` needs a
trailing space; `bin/tmux-agents` mirrors the same rule to keep its columns
aligned.

**Every glyph must carry `Emoji_Presentation=Yes` on its own**, never a base
character promoted with VS16 `U+FE0F`, because terminals and tmux disagree on
whether such a sequence is one cell or two. `⚠️` was tried for `asking` and
visibly misaligned the tab title, which is why the set is built from
single-codepoint shapes rather than from the signs these states would otherwise
want. `agent-state.test.sh` asserts that no published glyph contains `U+FE0F`.

**Hue answers one question, and it is not "which state is this".** At tab size
hue is all that resolves, and the only thing worth resolving there is whether it
is worth going to that tab. So hue groups:

| glyph | states | reading |
| --- | --- | --- |
| 🛑 red | `asking`, `waiting`, `needs_input` | blocked on you — go there |
| 🟢 green | `stalled` | the turn is over, nothing is blocked |
| ▶ none | `busy` | running; the one state you are *not* meant to look at |

Shape carries nothing further: **all three blocked states print the same 🛑**.
Which kind of block it is — a question, a permission prompt, an agent elsewhere
wanting input — does not change the answer to the only question this indicator
is asked, and a second visual axis for it only made the first one harder to
read.

Know the consequence before adding a state: **the glyph is no longer a key.** The
picker prints no state text, so a row's glyph no longer says *which* block it is
reporting. It does say that `ctrl-o` applies — the key is offered for all three
red states, which is what keeps "red" a single actionable category — but the
state itself still travels in the row's hidden key field, so anything that needs
to tell them apart reads that, never the rendering.

Both halves of this cost a revision to learn. 🔘 was worn by both `stalled` and
what is now `needs_input`, so "a worker is blocked on you" and "your turn
finished" rendered identically — and being grey it read as ▶ besides. Giving
different meanings one colour is the mistake; giving one meaning one colour is
the opposite move.

## One pane holds several actors

[Hooks fire inside subagents too, and the payload then carries `agent_id` /
`agent_type`](https://code.claude.com/docs/en/hooks), so a pane has as many live
states as it has actors: the main thread plus one per running subagent.

The first version published a single last-write-wins value, which cannot
represent that — with three subagents running, one hitting a permission prompt
published `waiting` and the next `PostToolBatch` from either of the others
overwrote it with `busy`, so the tab claimed progress while a dialog sat
unanswered.

State is therefore kept **per actor**, one small file each under
`${XDG_STATE_HOME:-~/.local/state}/claude-agent-state/<socket>-<pane>/`, and the
options are derived from them by priority:

    asking > waiting > needs_input > busy > stalled

so anything blocked on the human outranks anything still running. Ties go to the
oldest, then to whichever record carries a note. Several actors routinely enter a
state within the same second — `Stop` lands on the main thread while a worker is
already blocked — and without that last clause the main thread's noteless record
wins by being read first, hiding the one message that explains the glyph.

Files rather than more pane options, for two reasons: tmux formats cannot
enumerate options by prefix, so a per-agent option could be written but never
aggregated cheaply; and each hook writes only *its own* actor's record, so
subagents firing at once cannot lose each other's writes where one shared file
would need locking on the hottest path.

The per-actor listing is published back as `@claude_agents` — records separated
by ASCII `RS`, fields by `US`, because a note is arbitrary text from a prompt and
any printable delimiter would eventually appear inside one. That is what lets
`bin/tmux-agents` show a row per actor and, because it rides the same
`list-panes -F` format, works over ssh unchanged.

Keyed by socket *and* pane id: a pane id is only unique within one server.

`SubagentStart` / `SubagentStop` maintain the set. **`Stop` deliberately does
not clear it**, because a backgrounded agent outlives the turn that launched it
and dropping it there would hide exactly the agent most likely to be waiting on
you. The residue is a subagent that dies without firing `SubagentStop`, whose
`busy` record then sticks until `SessionStart`/`SessionEnd` clears the pane.

## A permission prompt belongs to nobody

**The `Notification` for a permission prompt carries no `agent_id`.** Measured
against 2.1.270 by logging raw hook stdin: a prompt raised inside a subagent
arrives as

    {"session_id":…,"message":"Claude needs your permission",
     "notification_type":"permission_prompt"}

byte for byte what the main thread's own prompt sends — no `agent_id`, no tool
name — while the `PostToolBatch` from that same subagent *does* carry one.

Filed against `main`, which is what this hook did until then, that published 🛑
at a thread which was not blocked, and it then **stuck**: a `waiting` record is
cleared only by that actor's own next `PostToolBatch`, and a main thread parked
on `Waiting for N background agents` fires none. The tab sat red for the whole
length of a subagent run with nothing on screen to answer — the inverse of the
masking bug the per-actor records were introduced to fix, and just as useless.

`PermissionRequest` is the surface that does carry `agent_id`/`agent_type`, plus
`tool_name` and `tool_input`, so attribution is taken from there and the prompt
lands on the actor that is really blocked. Two consequences worth knowing:

- **It publishes nothing.** It fires *before* the permission rules are applied,
  so it is not proof that a dialog opened — an allow-rule or auto mode settles
  most calls with no prompt at all. Publishing `waiting` from it would paint 🛑
  over every auto-approved long-running command until it finished. It writes a
  single `pending` record; the `Notification` remains the thing that means "a
  modal is open", and claims that record when it arrives.
- **The note gets better.** `Bash: rm -rf /tmp/x` instead of the contentless
  "Claude needs your permission", because `tool_input` is in that payload and
  nowhere else.

One `pending` slot, last writer wins: two prompts racing on one pane
misattribute the second, which is still strictly better than attributing every
prompt to a thread that is not blocked. A record left by a call that was allowed
*without* a prompt is dropped by the `PostToolBatch` that carries its result, so
the window in which a stale note exists is exactly the window in which a prompt
could be open.

An MCP server's `elicitation_dialog` raises no permission request, so it still
lands on `main` — where such a dialog almost always belongs.

## Registration

Registered on `SessionStart`/`SessionEnd` (clear — see below), `UserPromptSubmit` /
`PostToolBatch` (busy), `PreToolUse` with matcher `AskUserQuestion` (asking),
`PermissionRequest` (attribution only, publishes nothing), `Notification`
(waiting / needs_input), `Stop` (stalled), and `SubagentStart`/`SubagentStop`
(register / forget an actor).

Modes name the transition and states name what is published, so they need not
match: the `done` argv mode is the Stop transition and publishes `stalled`,
which also spares `settings.json` a lockstep edit.

### A resumed session opens `stalled`

`claude --continue` reopens a conversation that already holds a finished turn
whose next move is yours, so the pane says so from the moment it opens.
Previously a resumed session was indistinguishable from an empty shell until you
typed — the wrong way round, since the sessions worth finding again are exactly
the ones you left in the middle of something.

It keys on `SessionStart`'s `.source`, and **only `resume`**. `startup` and
`clear` are new conversations with nothing to have left unread. `compact` fires
**mid-turn** after auto-compaction while the agent is still working, so
publishing there would paint 🟢 over a busy session and the next `PostToolBatch`
would take it straight back — a flicker and nothing more. `fork` is arguably the
same case as `resume` and is left out only until it is wanted; it is one word.

**The field is read with `jq`, not matched in the string, and that is not
style.** `SessionEnd` also carries the literal `resume` — as its `reason`, when
the session ends because one was resumed elsewhere — so `case "$json" in
*resume*)` would light up a pane whose session had just *ended*. `.source` is a
different key and only `SessionStart` has one. This is the one `clear`
invocation per session, so the fork it costs is affordable where the `busy` path
would never allow it.

## Cost

It takes the transition as an **argv mode**, not from the stdin JSON's
`hook_event_name`, so the hot paths need not parse stdin at all: `PostToolBatch`
fires once per tool batch and exists solely to clear `waiting`/`asking` back to
`busy` once a prompt is answered, so it must stay cheap.

It reads stdin on the hot paths only while a subagent is actually registered on
the pane — with one actor there is nothing to attribute — and when it does, it
attributes with
**jq, never a shell regex over the raw payload**: `PostToolBatch` carries the
*content* of every tool result in the batch, so a file the agent just read can
contain the text `"agent_id"` and would silently file the main thread's state
under a subagent that does not exist.

`PermissionRequest` does spawn a `jq`, and that is affordable only because it is
a cold path: measured in auto mode it fires for the calls that need a decision
(an `rm` against an `ask` rule) and not for the allow-listed ones around them —
a plain `hostname` raised none. If a future version fires it per tool call, this
is the first thing to re-measure.

Publishing is skipped outright when the derived options are byte-identical to
what was last published, which is what pays for the file work: a subagent
reporting `busy` on a pane that is already `busy` now costs no fork at all, where
the previous version spent four `tmux` calls on every batch.

## The publish race

**The note is consulted only while no subagent is registered, and the hook
re-derives after publishing.** Both halves come from the same measurement.

The hook races with itself, because subagents launched in one message fire
`SubagentStart` simultaneously, and a copy whose scan missed a record another had
not written yet published a view short of an actor — 5 bursts in 15 at 16
concurrent starts.

It *stuck* rather than healing because the note was written before the options,
so the copy that set the options last could be the one whose note landed first,
leaving the file claiming the complete view while the pane held the short one and
every later event skipping as a no-op. And the record a copy misses can be the
blocked one, which puts the original bug back: the tab says `busy` while a dialog
waits.

(An earlier measurement of *how often* the glyph came out wrong was inflated by a
fixture that raced a `subagent-start` and a permission prompt for the **same**
actor — two writes to one record, so it ended `busy` on its own about one round
in ten, with no publish race involved. A subagent cannot be blocked before it has
started; the corrected fixture registers the blocked actor first, and reproduces
the short listing but not, reliably, the wrong glyph.)

Re-deriving after the write converges without a lock — every copy writes its own
record *before* deriving, so whichever copy sets the options last sees every
record written before its scan, and any record written after belongs to a copy
that has yet to publish — and re-deriving is free, being globs and `read`.

The note is now written after the options and is trusted only in the
single-writer case; a pane whose options are cleared from outside therefore stays
cleared until something changes, which is the accepted price of the fork-free hot
path and is pinned as such.

## Notes are stripped of control characters

Not merely collapsed to one line: RS and US separate the records, so a message
carrying one splits its own record and the picker renders a phantom row whose
state is the tail of the note. The text is not always Claude's own — an
`elicitation_dialog` message comes from whichever MCP server raised it.

## `asking` cannot come from `Notification`

Verified against 2.1.247 by logging raw hook stdin: an AskUserQuestion dialog and
a `Bash(rm …)` permission prompt send byte-identical payloads —
`{"notification_type":"permission_prompt","message":"Claude needs your
permission"}` — with no tool name anywhere. (The binary *does* contain a
`Claude needs your permission to use ${tool}` string; that is the
push-notification path, not the hook path, so grepping for it misleads.)

`PreToolUse` is the only surface where the two differ, because its matcher **is**
the tool name; as a bonus it lands when the dialog opens rather than after the
notification's delay.

The same emptiness is why `PermissionRequest` had to be added later: that
payload says nothing about *who* is being asked either. See the section above.

That makes state precedence real logic rather than incidental, and
`agent-state.test.sh` pins it: the same dialog fires both hooks, so
`permission_prompt` must not demote `asking` to `waiting`, and `agent_needs_input`
(a background agent blocking on the human) must not demote either of them to
`needs_input` — that is the one direction that loses information.

`idle_prompt` is deliberately **not** in the allow-list: it fires 60s after a
turn ends, a state `Stop` has already published, so republishing would only
restamp `@claude_since` and reset the picker's age column to `0s`. It earned its
keep only while `done` and `stalled` were separate glyphs.

## Eviction

No age cutoff anywhere, deliberately. State lives on the pane, so it cannot
outlive the tab holding it, and closing the tab is the eviction.

The residue is a session killed without its `SessionEnd` hook running whose pane
stays open — it keeps its last state until the pane closes, or until
`SessionStart` clears it when Claude is next started there.
(`pane_current_command` reports the Claude version string for a live session, so
liveness *could* be checked, but that is an undocumented implementation detail
and is not relied on.)

## Testing (`agent-state.test.sh`)

Runs against a **real** throwaway tmux server (`-L`, `-f /dev/null`), not a
stubbed `tmux` on `$PATH` — the contract is the pane options other things read,
so a stub would keep passing if tmux changed what `set-option -p` means.

Run it after editing the hook. Requires `tmux` and `jq`, and **fails rather than
skips** without them.

**The cases that earn their keep:**

- **`notify`** — the `notification_type` allow-list is a hard-coded list against
  an upstream vocabulary, and a rename there fails silently in both directions (a
  dropped type makes a blocked session invisible; a wrongly added one makes a
  glyph stick forever).
- **Precedence** — one AskUserQuestion dialog fires `PreToolUse` *and* an
  indistinguishable `permission_prompt` Notification, and `idle_prompt` can land
  on top of either, so which state may overwrite which is real logic — and a
  mistake there shows up only as the wrong glyph on somebody's tab. It also pins
  each glyph's exact spacing, which `set-titles-string` concatenates blind.
- **Attribution of a prompt** — every fixture that raises a permission prompt
  goes through `prompt_for`, which sends a `PermissionRequest` and then an
  *anonymous* `Notification`, because that is what Claude Code sends. Earlier
  versions of these cases put an `agent_id` in the notification and asserted a
  labelled note, pinning a payload shape that has never existed — which is how
  the bug survived a suite this size. The regression case is the one that
  matters: a subagent's prompt, a main thread parked on a background agent, and
  the assertion that main reporting `busy` does **not** clear someone else's
  dialog while the subagent's own batch does.
- **Multi-actor** — the regression suite for the bug that produced the per-actor
  records: a subagent's `busy` must not mask another actor's `waiting`,
  `SubagentStop` must be the only thing that removes an actor, `Stop` must keep a
  backgrounded one, attribution must come from the top-level key and not from
  tool output that merely contains the text, and `@claude_agents` must survive a
  `list-panes -F` round trip — that last one is the contract with
  `bin/tmux-agents`, including over ssh, and is the reason the separators are
  control characters.
- **Concurrency** — the ones that found a real bug rather than pinning a
  decision, and they come in two halves on purpose. The burst of simultaneous
  `subagent-start`s is a smoke test only, since it produced a short listing in 5
  rounds of 20 at 16 concurrent starts and 2 of 20 at 12, varying with machine
  load — a probabilistic red is not a guard. The deterministic sibling clears the
  pane options behind the hook's back, which reaches the same end state as the
  interleaving, and asserts a registered blocked actor reappears.
- **Cost** — three cases assert cost rather than output: no JSON parsing on the
  busy path while the pane has one actor, one jq pass once a subagent is
  registered, no tmux round trip when nothing a consumer can see has changed.
  Those are documented invariants that no functional test notices: break them and
  everything still passes, the hook merely taxes the inner agent loop. They wrap
  the real `jq` and `tmux` rather than faking them, since what is counted is how
  often each is reached.

Sections double as the reset point and a failure names the section it came from,
because `assert_opt` can only describe a value and this file is one long script
rather than a set of named cases.

The test points `XDG_STATE_HOME` at a temp dir: without that it writes into — and
`clear` deletes — the records of the sessions the developer has open.
