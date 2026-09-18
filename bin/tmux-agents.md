# tmux-agents

Pick a Claude Code agent by state and jump to its WezTerm tab. Bound to
`prefix + a`.

Rows come from the pane user options that `root/.claude/hooks/agent-state.sh`
publishes (`@claude_state`, `@claude_glyph`, `@claude_since`, `@claude_note`,
`@claude_agents`) — see [agent-state.md](../root/.claude/hooks/agent-state.md)
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
  `msg()` and the `switch-client` fallback, both post-selection).

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

**BSD sed does not expand `\t` in a replacement**, so the tab is built as a
variable.

**Glyph padding is baked into `@claude_glyph`, and this script mirrors the same
rule** to keep its columns aligned: emoji-presentation glyphs already occupy two
cells, while the narrow `▶` needs a trailing space.

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

`ctrl-o` is offered only for a session with a dialog open (`asking` /
`waiting`): for a `busy` or finished one the view would be no more than a second
way of looking at a tab that is one keypress away. `needs_input` is **not**
included even though it too is blocked on the human — the notification says an
agent wants input, not that a dialog this view could answer is on screen — so it
is left out until that turns out to be wrong in practice. The state therefore rides in
the row's hidden key field alongside the ids — deriving it from the glyph
afterwards would mean reading the rendering back.

**Refusing does nothing at all, and never falls back to the jump**: the two keys
mean different things, and a `ctrl-o` that quietly moved you to another tab is
worse than one that does not fire. It is refused *inside fzf*, per row, rather
than after the picker has closed — closing the popup and printing to the status
line is itself something happening, and what is wanted is a warning and nothing
else. So `ctrl-o` is a `transform` binding that reads the hidden key field and
either returns `print(ctrl-o)+accept` or only rewrites the header, with a `focus`
binding putting the hint back as soon as the cursor moves.

`print(...)+accept` reproduces exactly what `--expect` emitted (the key on its
own first line, empty for `enter`), which is the documented idiom.
**`--expect` cannot be combined with a `--bind` on the same key** — the binding
replaces it and every `ctrl-o` then reads as a plain `enter`, i.e. as a jump.
The shell-side checks are kept behind it as the ones a headless test can reach.

## Remote hosts

Remote hosts need no transport of their own for the tab glyph — the same
dotfiles run there, so the remote tmux's `set-titles` already embeds its glyph
and it arrives inside the local `#{pane_title}` via OSC 2 (rendering as
`host:🔺 name`, glyph after the host, since the remote sends one opaque string).

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

Assertions that look subtler than they are:

- The ▶ glyph's padding is only observable on a row whose age is four characters
  wide (`111h`), because `%4s` right-alignment supplies the missing space for
  the usual three-character age and the test passes either way.
- The picker must print an **empty first line** for a plain enter: misread it by
  one line and the jump targets nothing, which looks exactly like tmux ignoring
  the key. The fixture puts the agent in a window's *second* pane and asserts on
  `select-pane`.
- A refused `ctrl-o` must not jump and must leave no mirror session behind.

`--jump-check` is pinned on its own, headlessly: it is the half that decides, it
needs no pty, and each answer is a different silent failure — accepting a row
that cannot be jumped to makes `enter` close the popup and do nothing, refusing
one that can makes `enter` dead.

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
