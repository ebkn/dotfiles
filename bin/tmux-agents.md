# tmux-agents

Pick a Claude Code agent by state and jump to its WezTerm tab. Bound to
`prefix + a`, with `prefix + A` as the picker-less shortcut described below.

Rows come from the pane user options that `root/.claude/hooks/agent-state.sh`
publishes (`@claude_state`, `@claude_since`, `@claude_note`, `@claude_agents`,
`@claude_session_id`) — see [agent-state.md](../root/.claude/hooks/agent-state.md)
for what those mean and how they are derived. `ctrl-o` hands a blocked agent to
[tmux-agent-view](tmux-agent-view.md).

## Latency is the design constraint

The popup is already on screen when the script starts, so everything before
fzf is time spent looking at an empty box. There is no real computation here —
measured on this machine, a tmux round-trip is ~5ms and a process spawn ~1.6ms,
and those two numbers *are* the runtime.

It went from 13 external calls to 6 (45ms → 25ms) by:

- making one `tmux list-panes` carry the ssh columns too, instead of a second
  listing;
- letting the remote tmux write the host column through the format string,
  instead of a local `sed` per host;
- keeping rows in a shell variable, so `mktemp`/`cat` are paid only when a
  remote host actually exists;
- folding rank and render into one awk pass;
- deferring `tmux list-clients` until after something is picked (it feeds only
  `msg()` and the answer view's client, both post-selection).

Adding a convenient pipeline stage here is not free; it is ~2ms of visible lag.

## Traps

**`IFS=$'\t' read -r a b c …` silently mangles the rows.** Tab is an IFS
*whitespace* character however narrow IFS is, so runs of tabs collapse and
leading ones are stripped — and an ordinary pane has `@claude_state`,
`@claude_since` and `@claude_note` all unset, so a ten-field row arrives as six
with everything after the first gap shifted. `awk -F'\t'` does not do this,
which is why the awk version never had to know. Peel trailing columns off with
`${row##*"$TAB"}` instead of counting fields.

**A `,` inside a `#{P:...}` loop body terminates the body.** That is why the
glyph is pre-computed into `@claude_glyph` by the hook rather than derived with
`#{?@claude_state,…}` in the format.

**tmux does not interpret `\t` in a `-F` format**, so the tab is built as a
variable.

**Glyph padding is baked into `@claude_glyph`, and this script mirrors the same
rule** to keep its columns aligned: emoji-presentation glyphs already occupy two
cells, while the narrow `▶` needs a trailing space.

## The list corrects itself, because the hooks cannot

**Three transitions have no hook at all**: a permission prompt being answered, a
dialog being dismissed, and a turn being interrupted. The
[documented event list](https://code.claude.com/docs/en/hooks) contains none of
them, and reading 2.1.275 confirms it. So the pane options this picker reads go
stale in exactly the situations it exists to show — measured, 🛑 arrives 6s after
the dialog (a `setTimeout` the app cancels if you answer sooner), then stays for
the entire run of the command you approved. See
[agent-state.md](../root/.claude/hooks/agent-state.md).

`claude agents --json` is the documented way to read the live answer: the
[agent-view docs](https://code.claude.com/docs/en/agent-view) name a status bar
as the use case, and say in the same breath that the files underneath are not a
stable interface. It costs ~140ms and returns `status` (`busy` / `waiting` /
`idle`) with a `waitingFor` reason.

**It says nothing about tmux**, which is why `agent-state.sh` publishes
`@claude_session_id` on the pane: the hook is the only thing that knows
`$TMUX_PANE`, and the CLI is the only thing that knows the state. The join is
the whole mechanism.

The split follows from the latency budget: the first list is drawn from the pane
options alone, as before, and the correction arrives with the first refresh a
moment later. `--rows` is that corrected render, re-entered by fzf.

**`prefix + A` pays it up front instead.** It acts on one row without showing
you any of them, so it is the one path that cannot afford a stale state — it
would open a session that has already been answered, or report "nothing is
waiting on you" while a dialog whose 🛑 is still 6s away sits open. 140ms before
a popup opens is not noticeable; 140ms before the picker paints is the whole
budget.

What the merge does, and does not, do:

- **"Blocked" here means every state that prints 🛑** — `asking`, `waiting` and
  `needs_input` — which is the same rule `ctrl-o` is offered by. Leaving one out
  leaves exactly that state stuck red, and it is the kind of gap a merge opens
  quietly: `needs_input` arrived after this correction was written, and the
  pinned case is what caught it.
- **Only the blocked/not-blocked disagreement is acted on.** When the two agree,
  the hook data is kept whole — its note names the tool (`Bash: rm -rf …`) and
  its per-actor listing names *which subagent* is blocked, and the CLI knows
  neither.
- **A contradicted per-actor listing is dropped**, not re-rendered: it is
  derived from the same records that were just contradicted, so keeping it would
  put the stale rows straight back and the correction would be invisible.
- **An unrecognised status is left alone.** The vocabulary belongs to the CLI,
  and mapping an unknown one onto a glyph invents a state.
- **`shell` is not one of those**, though it was treated as one at first. The CLI
  publishes four statuses — `busy`, `shell`, `idle`, `waiting` — and derives the
  third as `status === "idle" && <the user is at a shell> ? "shell" : status`, so
  it is a flavour of `idle`, which already means not blocked. Read out of the
  installed bundle (2.1.284), not inferred from watching it. Leaving it
  unrecognised made it the one value that could **strand a pane red forever**: no
  hook reports the transition into a shell either, so this poller is the only
  thing that could clear the glyph, and it declined to. A genuinely unknown value
  still has a case, with a status no CLI would emit.
- **Only local rows are corrected.** A remote pane's session is known to the
  remote machine, and asking it would be an ssh round trip per refresh.
- **Every failure degrades to the uncorrected rows** — a missing CLI, a rename,
  malformed JSON. An indicator that disappears when a CLI changes is worse than
  one that is late.
- **The age of a corrected row means "since this was last confirmed"**, not
  "since the state was entered": the CLI publishes no timestamp for its status,
  and keeping the hook's would date a state it disagrees with.

## `--sync` — the same correction, written back onto the panes

`--rows` fixes the picker and nothing else. The WezTerm tab glyph is read
straight out of `@claude_glyph` by `set-titles-string`, so without this a tab
stays red for the whole of an approved command and keeps whatever glyph it had
through an interrupt — which is the symptom that is actually noticed, since the
tab bar is always on screen and the picker is not.

`--sync` is run from launchd
(`launchd/com.ebkn.tmux-agent-sync.plist`, every 5s). **It is a mode of this
script, not a script of its own**, and that is the point: the rule deciding what
to correct would otherwise exist in two copies that drift — which is precisely
how `needs_input` came to be missing from the one above.

- **It applies the correction by calling the hook** (`agent-state.sh correct`),
  never by setting the options here. `publish()` skips its tmux calls while the
  records still match what it last published, so an option written behind its
  back would make the *next* genuine transition a no-op. Which actor records a
  correction reaches is [the hook's rule](../root/.claude/hooks/agent-state.md),
  not this script's.
- **Only rows the correction actually changed are applied.** `correct_rows`
  prints every row either way, so the two listings are compared; without that, a
  tick would set four options and force a redraw on every pane, forever. Pinned
  by a case that counts hook invocations, because nothing about the *result*
  differs.
- **A tick with no Claude session under tmux costs one `tmux list-panes`.** The
  CLI call is guarded by "does any pane carry a binding", so an idle machine
  pays essentially nothing and the interval can stay short.
- **A pane the CLI agrees with is left alone, including a blank one.** An idle
  session whose hooks published nothing must not acquire a 🟢: "agree = do
  nothing" is what stops a poller lighting up every Claude pane on the machine.
- **It never reaches a remote pane** (`collect_rows local`): an ssh round trip
  per tick is not a cost a background timer may impose, and a remote session's
  state is not this machine's to correct anyway.

`$TMUX` is constructed rather than inherited — under launchd there is none — and
the hook reads only its first field, the socket, to key its records.

**Every tmux call whose output is split on TAB passes `-u`.** A tmux client
prints control characters in a `-F` format as `_` — TAB included — unless it
believes the terminal is UTF-8, and it believes that if the locale says so **or
if `$TMUX` is set**. launchd provides neither, so until `-u` the job read every
row as one field, found no pane bound to a session, and returned early on every
tick: loaded, `last exit code = 0`, an empty log, and the tab red while the
picker was green — the exact symptom this mode exists to remove, for as long as
it had existed. Nothing run from inside tmux could see it, the picker and a
manual `--sync` included, because `$TMUX` alone is enough to hide it. `-u` is a
flag rather than an exported locale because a locale name valid on macOS need
not exist on Linux, and it adds no process. The case pinning it runs `--sync`
with **both** the locale and `$TMUX` removed, against a server on the default
socket of a private `TMUX_TMPDIR` (`bare_tmux` in the suite) — run_sync's `$TMUX`
would mask it. The remote listing needs the flag for the same reason, since an
ssh exec has no `$TMUX` and a locale only if SendEnv and AcceptEnv agree; the
canned ssh stub never runs the remote tmux, so a second case has its stub run
the command for real under that stripped environment.

To check the live job end to end, publish a stale 🛑 through the hook on an
**idle** session's pane (one whose own hooks will not fire and clear it first)
and watch it go back within a tick:
`TMUX=<socket>,0,0 TMUX_PANE=<pane> ~/.claude/hooks/agent-state.sh correct waiting probe`.

**The three corrected columns are read back with `IFS=$'\t' read`**, which works
only because `pane` and `state` are never empty and the note is last: tab is an
IFS *whitespace* character, so an empty field anywhere else shifts the rest by
one. That is the same trap the pane listing documents above, and it is the thing
to check before adding a column. The note itself is safe because the CLI's
`waitingFor` reaches it through jq's `@tsv`, which escapes a tab rather than
emitting one.

## Refreshing while it is open

`start` corrects the first list as soon as the picker is up; `load` fires again
after every reload, which is what makes it a loop, with the wait supplied by a
`sleep` at the head of the reload command. `REFRESH` is a comfort/cost dial — the
list is correct the moment it is drawn either way.

**The sleep must be inside the reload command, never in a `transform`.** A
transform runs synchronously, so a version that slept there froze the picker for
`REFRESH` seconds at a time and swallowed keystrokes; it looked like an `enter`
that did nothing. The pty cases in the test caught it.

`reload-sync`, so the list is replaced only when the new one is complete and
never blinks empty. **The cursor needs no help**: measured against fzf 0.74 it
stays on the same row index across a `reload-sync`, so there is no `pos()` dance
here — and if that ever changes, a list that jumps to the top every `REFRESH`
seconds cannot be navigated, which is the symptom to look for.

## Jumping to a tab

`enter` raises the agent's WezTerm tab. Two things make that harder than it
looks.

**`wezterm cli activate-tab` switches the tab inside the window that owns it but
never raises that window**, so a pick landing in another WezTerm window used to
change nothing visible. The CLI has no window-focus verb (checked on 20240203)
and `window:focus()` is Lua-only, so this script writes
`OSC 1337 SetUserVar=focus_window` to the target pane's **own tty** — WezTerm
attributes it to that pane and hands the `user-var-changed` handler in
`wezterm.lua` the owning window. The tty is the link that already exists
(`client_tty` = `tty_name`), the value is ignored, and re-setting the same value
fires again. Editing either side without the other silently reverts to the
no-op.

**A window shown by an ssh client never reaches WezTerm, so the CLI is not run
at all.** tmux already knows which those are: `SSH_CONNECTION` is in the default
`update-environment` list, so the attaching client copies it into the session
environment and one `show-environment -t <session>` reads it back. Note it
prints `-NAME` for a variable that is *unset* there, so only the `NAME=value`
shape counts. Reading `$SSH_CONNECTION` out of this process would be wrong —
that is the tmux **server's** environment, whatever it was started with, which
says nothing about the client showing that window now. On a remote host this is
the state of every row, so it turns the common answer into two tmux calls and no
process spawn.

**Every `wezterm cli` call carries `--no-auto-start`, and that flag is a latency
fix, not a correctness one.** Without it the CLI tries to *start* a mux server
before admitting there is none — measured here at **3.0–3.4s against 0.00s**,
while every other step on the jump path costs 0ms. That whole delay sat between
pressing `enter` and the warning, on exactly the hosts where the warning is the
normal answer. It cannot cost anything in the success case either: the default
is to prefer a running gui instance, and the flag only forbids starting one.
A missing flag is invisible to every other assertion — the jump still works, it
is just slow — so `tmux-agents.test.sh` asserts on the flag itself.

**When there is no such tab it warns *in the picker*, which stays open.** Same
shape as a refused `ctrl-o`, and for the same reason: closing the popup and
printing to a status line behind it is not an answer to "why did nothing
happen". It cannot be decided from the row the way `ctrl-o` is, since whether a
WezTerm tab shows that window takes tmux and possibly `wezterm` to work out — so
the binding re-enters this script as **`--jump-check <key field>`**, which prints
the fzf actions (`print()+accept`, or a lone `change-header`). That mode and the
jump call one `resolve_jump`, deliberately: a row the picker accepts must be one
the jump agrees it can act on, or `enter` closes the popup and does nothing. The
cost is paid only on the keypress, never on the latency path before the picker.

It used to fall back to `switch-client`, which is worse than doing nothing: it
repoints the tab you are sitting in at somebody else's window, leaving two
clients on one session — the state [tmux-session-swap](tmux-session-swap.md)
exists to prevent — and it is not what `enter` means. A picker run on an ssh
host can never reach the WezTerm in front of you (measured: no `wezterm-gui`
process there at all, and `wezterm cli list` fails against a dead
`gui-sock-<pid>`), so on a remote every row is unjumpable and the answer is
`prefix + w`, which the warning names. `select-pane` sits below that check for
the same reason — refusing must leave the agent's window untouched.

## Offering ctrl-o

`ctrl-o` is offered for every state that is blocked on the human — `asking`,
`waiting` and `needs_input`, i.e. exactly the rows the 🛑 glyph covers. For a
`busy` or finished one the view would be no more than a second way of looking at
a tab that is one keypress away.

`needs_input` was excluded at first, on the grounds that the notification says an
agent wants input rather than that a dialog this view could answer is on screen.
That reasoning does not survive what the view actually is: it is not a rendered
summary but a grouped session attached to the **real** window (see
[tmux-agent-view.md](tmux-agent-view.md)), so keys reach the agent's own pane
whatever is on it. There is nothing for `needs_input` to fail at, and excluding
it only made the key dead on a row the tab bar had just painted red. The gate is
therefore the same set the glyph is, which is also what `prefix + A` needs in
order to mean "answer the first red one".

The state rides in the row's hidden key field alongside the ids — deriving it
from the glyph afterwards would mean reading the rendering back, and since all
three blocked states share one glyph it could no longer be derived at all.

**Refusing does nothing at all, and never falls back to the jump**: the two keys
mean different things, and a `ctrl-o` that quietly moved you to another tab is
worse than one that does not fire. It is refused *inside fzf*, per row, rather
than after the picker has closed — closing the popup and printing to the status
line is itself something happening, and what is wanted is a warning and nothing
else. So `ctrl-o` is a `transform` binding that re-enters the script as
**`--answer-check <key field>`** — as `enter` does with `--jump-check` — which
returns `print(ctrl-o)+accept` or only rewrites the header, with a `focus`
binding putting the hint back as soon as the cursor moves. The decision is
`answer_verdict` (`ok` / `remote` / `idle`), the one function `prefix + A` and
the check after the picker also ask; "blocked" is `BLOCKED_STATES`, the one list
the 🛑 glyph, the ranking and `correct_rows` read too.

`print(...)+accept` reproduces exactly what `--expect` emitted (the key on its
own first line, empty for `enter`), which is the documented idiom.
**`--expect` cannot be combined with a `--bind` on the same key** — the binding
replaces it and every `ctrl-o` then reads as a plain `enter`, i.e. as a jump.
The shell-side checks are kept behind it as the ones a headless test can reach.

## `--answer-first` (`prefix + A`)

The one move you make when the tab bar has gone red: collect, rank, open the
answer view on the top blocked row. No list is drawn and nothing is picked.

It is a **separate key**, not an option on `prefix + a`, because the two answer
different questions. `a` is "show me what is running"; `A` is "there is one
thing to do, do it". Drawing a popup only to accept its own first row would be a
flash of a list nobody reads — the ranking already puts the most urgent blocked
agent (rank, then age) on top, which is the row you would have picked. When more than one is
blocked nothing is lost by not starting at the list, because the answer view
reopens the real picker on the way out ([tmux-agent-view.md](tmux-agent-view.md)).

The row is chosen by the **same function `ctrl-o` is offered by**:
`answer_verdict`, applied to each row's hidden key field in ranked order, and
the first `ok` is the pick. That is the invariant worth keeping — if the two ever
disagree, `A` becomes a key that does something `ctrl-o` on the same row refuses,
with no list on screen to show what it picked. Until both asked one function
they each carried their own copy of the blocked set (an awk regex here, a
`case` in the binding), which the code claimed could not drift.

**The client is passed in**, unlike `prefix + a`. This does not run in a popup;
it runs under `run-shell`, whose child's `$TMUX` names the **server**, not which
of its clients pressed the key. `run-shell` *does* expand `#{...}` in its command
(`display-popup` does not — that asymmetry is what forces the popup path to
derive the client from `$TMUX`), so the binding hands over `#{client_name}`. The
binding also spells the script's **absolute path**, because `run-shell` uses the
tmux server's environment and its `$PATH` need not hold `~/.local/bin`.

**Every way of choosing the wrong row is silent**, which is what the tests assert
against: a busy row opens the view on an agent that is not blocked, no row makes
the key dead, a remote row hands `display-popup` a window id from another
server. So `tmux-agents.test.sh` asserts on *which window the mirror is showing*,
never merely that a mirror exists.

Not finding a row is three different silences, and they are told apart on the
status line — nothing running, something red this key cannot reach (a remote
agent), and everything running fine. A key that does nothing and says nothing is
indistinguishable from tmux having dropped it.

It runs before the empty-list branch below it, deliberately: that branch holds
the popup open until a key is pressed, and there is no popup here — it would
hang a backgrounded `run-shell` job forever with nothing on screen to explain it.

**Latency is not free here the way it is in the picker.** `prefix + a` pays the
remote fan-out with a popup already on screen; `A` pays it with nothing on
screen, so a `myssh` pane to a host that is asleep costs up to `ConnectTimeout=3`
of a key that looks dead. Shared with `prefix + a` deliberately — a shortcut that
could not reach a remote agent would be a second, quieter definition of "red".

## The count in the WezTerm tab bar

`prefix + A` is named by an indicator in WezTerm's tab bar (the `update-status`
handler in `wezterm.lua`), which shows `🛑 N  C-q A` whenever any agent is
blocked and nothing at all otherwise.

It is derived from the **tab titles**, not from tmux, and that is the only reason
it can exist at all: tmux formats have no loop over panes outside the current
window (`#{P:...}` is per-window), so a global count cannot be a format, and the
fallback is a `#()` subprocess on `status-interval` — exactly what the pane-option
design in [agent-state.md](../root/.claude/hooks/agent-state.md) exists to avoid.
Reading titles WezTerm already holds costs no process and no tmux round trip.

The consequence is that it agrees with the tab bar **by construction**, including
when the tab bar is wrong. That is the right direction to be wrong in for an
indicator whose only job is to explain what the tabs are already showing.

What it adds over the glyphs on the tabs themselves: one fixed place to look
rather than a row of titles that shrink and reorder, a count, the key, and
**every WezTerm window** — a red tab in a window behind this one has no other way
of reaching you.

## Remote hosts

Remote hosts need no transport of their own for the tab glyph — the same
dotfiles run there, so the remote tmux's `set-titles` already embeds its glyph
and it arrives inside the local `#{pane_title}` via OSC 2 (rendering as
`≫ 🛑 name`, glyph after the ssh marker, since the remote sends one opaque string).

The cost is that a remote contributes only its client's *active* window. This
picker sees all remote windows because it queries over ssh, restricted to
`@ssh_my_machine` hosts and using a ControlMaster socket separate from the one
`myssh` deliberately disables.

No age cutoff is applied, deliberately: state lives on the pane, so it cannot
outlive the tab holding it, and closing the tab is the eviction. A list that hid
old-but-open sessions would disagree with the tab bar it exists to explain.

The calling client is derived from `$TMUX`, because `display-popup` expands
formats only in `-d` — see [tmux-popup.md](tmux-popup.md).

## Testing (`tmux-agents.test.sh`)

Runs against a throwaway tmux server carrying real pane options, since that is
the actual contract. It needs no seam in the script: the finished list goes to
fzf on stdin, so a stub `fzf` that copies stdin out and exits non-zero captures
exactly what the user would have seen and makes the script take its `|| exit 0`
path before the jump.

Two traps found while writing it, both of which made the scripts look broken
when they were not:

1. **A pane running a real shell fights the test.** The shell sources
   `zsh/directory.zsh`, whose precmd hook clears `@git_branch` when the pane is
   not in a git repository — which a temp directory never is — so options set
   right after creating a window are wiped a few hundred milliseconds later.
   Every pane in these tests runs `sleep`, never a shell.
2. A window-name counter incremented inside `$( )` is lost to the subshell, so
   every window ends up with the same name and `-t <name>` silently resolves to
   the first. Window **ids** are used instead.

**Remote cases** cover the half with no local equivalent, and they exist because
that path went from an awk pass to a shell loop. Its failure is the quiet kind —
remote agents simply stop appearing, on a machine where you rarely have a remote
pane open to notice. The stub `ssh` stands in for the remote tmux and derives the
host column from the `-F` argument it was handed rather than hard-coding it,
because the host is now prefixed by the *remote* side through the format string;
get that wrong and the column comes out empty and the row reads `local`. The
dedup case (two panes, one host, one `ssh` invocation) pins the `case` in the
host loop. These caught the `IFS=$'\t'` collapse above on the first run, which
is the whole argument for having them.

**Per-actor cases** pin the other direction: a pane carrying `@claude_agents`
contributes one row per actor and **not** an extra row for the aggregate, which
is derived from exactly those records and would otherwise count one of them
twice; a record with an empty state is skipped rather than rendered as a
plausible grey circle; the blocked subagent keeps its own glyph and note rather
than the pane's, and its key carries **its** state, so `ctrl-o` is offered on the
row that is actually blocked and not on a busy sibling in the same pane; and it
joins the same ranking, so it sorts above every busy row including the two from
its own pane. A pane without that option — an older session, or a remote host
running older dotfiles — must still render from the aggregate, so both paths are
exercised in one run. One remote pane carries a listing too, which is the only
place those control-character separators cross an ssh transport and a remote
tmux's own format expansion.

**A listing that arrived escaped** gets a case of its own, because a remote tmux
older than the pinned one stores the separators as the literal characters `\036`
/ `\037` (measured on 3.4; see
[agent-state.md](../root/.claude/hooks/agent-state.md)). `collect_rows`
normalises them back, and the case is written as that literal text rather than by
installing an old tmux: what the consumer has to cope with is the bytes that
arrive, and those are measured elsewhere. It asserts three things, and the count
is the weakest of them — a mutation that normalised `RS` but not `US` still
produced one row per actor, and was caught only by the assertions that the fields
are separated and that no escape sequence survives into the rendered row. The
real 3.4 is checked by hand, end to end, not from CI, which has one pinned
version by design.

**Its mirror image has a case too**: a listing the current tmux wrote whose
*note* contains `\036` as literal text. Normalising that would split the record,
so the rule is per row and keyed on whether a real `RS` is present. Without it
the fixture renders three rows for two actors, the third a plausible green idle
one made of the note's tail — which is how the case was written.

**Correction cases** drive `--rows` directly, with a stub `claude` — the real one
would answer about the sessions the developer has open, which are not the
fixtures. They pin both directions of the disagreement (a stale 🛑 becoming ▶, a
dialog the hooks have not reported yet becoming 🛑), that a contradicted listing
is dropped rather than re-rendered, and the three cases where nothing may
change: an unrecognised status, a pane with no `@claude_session_id`, and a CLI
that fails. Each was confirmed against a mutated script — with the join
disabled, the first three fail and the last three still pass, which is what
tells them apart from a case that would pass either way. One case covers each of
the three red states rather than just `waiting`, which is what caught
`needs_input` being left out of the merge; another drives `prefix + A` against a
red the CLI calls gone, because that key picks its row from the same list and
must not drift from it.

**`--sync` cases** reuse those same fixtures and assert the pane **options**
instead of the rendering, because that is the surface the tab glyph reads. They
run the real hook, reached through a fixture `$HOME` rather than a variable
pointing the script elsewhere — the script keeps no seam that exists only for
the test — so what is pinned is the end of the whole path rather than an
intention to call something.

**Including `@claude_agents`, not only the aggregate.** `--rows` drops a
contradicted listing rather than re-rendering it, but that is the picker's own
view; the option left on the pane is what the *next* reader sees. A pane whose
`@claude_state` says busy while its listing still holds a `waiting` record goes
red again the moment anything expands it, and nothing noticed that until a case
asserted it. Asserted in both directions, because "no longer says waiting" is
also what an empty option says, and clearing the listing would be a different bug
wearing the same result. Confirmed by stopping the hook writing the option: the
stale record survives and the case fails.

**Four of them assert cost, and they are the ones that earn their keep**, since
none of them changes anything an option-level assertion could see:

- A tick that agrees with every pane spawns **no hook at all**, and a tick with
  one disagreement reaches that pane and no other. Re-applying a state a pane
  already holds is a no-op by the time it reaches tmux, so dropping the
  comparison that finds the changed rows is invisible except to a counting stub.
- A tick **never opens an ssh connection**. The remote fixtures live further
  down the file, so at that point there is no `@ssh_my_machine` pane for a
  missing `collect_rows local` to fan out to — the case makes one.
- A tick with no pane bound to a session **does not run the CLI**. Asserted just
  after the fixtures are killed, which is the only moment in the file where that
  is true.

Beside them: the binding survives a correction (losing it makes the pane
permanently uncorrectable, which no glyph would show), a bound but blank pane
the CLI calls idle stays blank, a failing CLI leaves every pane untouched, and a
tick with **no tmux server at all** — the state a launchd job spends most of its
life in — exits 0 saying nothing, or the log named in the plist grows by a line
every five seconds forever.

Assertions that look subtler than they are:

- The ▶ glyph's padding is only observable on a row whose age is four characters
  wide (`111h`), because `%4s` right-alignment supplies the missing space for
  the usual three-character age and the test passes either way.
- The picker must print an **empty first line** for a plain enter: misread it by
  one line and the jump targets nothing, which looks exactly like tmux ignoring
  the key. The fixture puts the agent in a window's *second* pane and asserts on
  `select-pane`.
- A refused `ctrl-o` must not jump and must leave no mirror session behind.

**`--answer-first` cases** run through `run-shell` with the client passed in,
because that is how the binding runs it, and they assert on **which window the
mirror is showing** rather than on a mirror existing: choosing a busy row opens
the view on an agent that is not blocked, and choosing a remote one hands
`display-popup` a window id from another server — which does not fail, since
`@9` exists locally too, so the key would quietly mirror an unrelated window.
The refusals are read out of `show-messages`, server-wide rather than
`-t <client>`: the command log records `display-message` with its argument,
which answers the question the test is really asking — *which branch ran* — where
"no view opened" would pass just as well for a script that died on line one. The
needle is the whole sentence, since that log keeps growing across sections —
and for the same reason **its presence proves nothing; its count does.** Two
prefix + A cases refuse with the same sentence, so the second was satisfied by
the first one's line whether or not its own run got as far as deciding. Each
refusal case now records the count before acting and waits for it to rise
(`wait_said`), which also replaces a fixed `sleep 2`: once the refusal is logged
the branch has been taken, so the "no mirror" check after it is not early.

Two harness traps, both of which made these pass or fail for the wrong reason:

1. **Detaching a mirror is asynchronous.** The `ctrl-o` cases above leave one
   attached to `ask-win`, and the first `--answer-first` case expects exactly
   that window — so without waiting for the count to reach zero it passed in full
   with `--answer-first` never having run. Hence `drop_mirrors` waits, and the
   wait is itself a case. **Opening one is asynchronous too, in two steps:**
   `tmux-agent-view` creates the mirror session and attaches to it after, so
   "the session exists" is not "the view is open". `wait_mirror` waited for the
   session and then read the clients, which under load found none ("the view is
   showing []") — and the attach that landed late had no client yet when
   `drop_mirrors` detached, so it outlived the drop and failed the next case
   too. That was the suite's flake under amd64 emulation (two prefix + A cases,
   roughly one run in three). `wait_mirror` now waits for an attached client,
   the ctrl-o case waits through it, and `drop_mirrors` repeats its detach
   inside the wait. Measured by delaying that attach by 3s: four cases failed
   before, none after.
2. **The remote section deletes its `ssh` stub** when it is done, deliberately,
   so the local cases cannot pick it up. The remote `--answer-first` case
   therefore brings its own in `$work/sshstub` — the same reason `$work/wstub`
   exists for the `wezterm` stub. Sharing `$work/stub` looked like it worked and
   silently used the **real** `ssh`, which fails a connection to `bakery` three
   seconds after the assertion has already given up.

`--jump-check` is pinned on its own, headlessly: it is the half that decides, it
needs no pty, and each answer is a different silent failure — accepting a row
that cannot be jumped to makes `enter` close the popup and do nothing, refusing
one that can makes `enter` dead. `--answer-check` is pinned the same way, for
every state in and out of the blocked set; it needs no tmux at all, since its
decision is in the key field.

One trap in driving the binding end to end: **fzf runs a `transform` through
`$SHELL`, and `zsh -c` rebuilds `$PATH`**, so a stub placed on the test's PATH is
invisible to it and the success path silently takes the refusal branch. The test
sets `SHELL=/bin/sh` for the picker.

A further section drives the **real** fzf, and it covers `enter` as well as
`ctrl-o` — the two are separate features and the tests have to keep them that
way. Every other case stubs the picker, so the binding `enter` actually runs
(`enter:print()+accept`, which replaced `--expect` when `ctrl-o` became a
`transform`) had no coverage at all. That section runs the picker in a real pane
(fzf needs a terminal), sends keys with `send-keys`, and asserts on the rendered
screen; `remain-on-exit` keeps the pane readable after fzf accepts, which is how
acceptance is told apart from a binding that quietly did nothing.

The suite's own long-standing flake — about one run in ten failing with no pty
client — turned out to be **a platform probe**: the BSD/GNU `script(1)` split was
decided by *running* `script -q /dev/null true` and seeing whether it succeeded,
and that probe spawns a pty of its own. When it failed, the code fell through to
the GNU spelling on a BSD `script`, which answers `illegal option -- c` and
leaves no client behind. A platform is not something to discover by trial; it is
`$OSTYPE` now. Two more silent traps sat behind it: `script` copies its own
stdin into the pty and exits when that closes, so a `sleep` is piped in to hold
it open (killed by the trap, or it would hold the caller's stdout for two
minutes); and **`$TMUX` has to be cleared for the attach**, because the suite is
normally run from inside tmux and tmux then refuses the attach as nested even
though the socket differs — again with no client and no message anywhere the
test could see.
