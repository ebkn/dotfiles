# tmux-agent-view

Answer a blocked Claude Code agent without leaving the tab you are in. Reached
from [tmux-agents](tmux-agents.md) (`prefix + a`) with `ctrl-o`; `enter` there
jumps to the agent's tab instead.

`ctrl-o` shows that agent's window in a popup on the current tab, so a
permission prompt or an `AskUserQuestion` can be answered in place.

## Why a mirror and not a rendered summary

The dialog is a TUI in the pane and there is no API for it, so this reduces to
showing the pane and getting keys into it. Since the dialog being answered is
the one that *approves command execution*, what you answer must be what you see.

That rules out driving it from `@claude_note`: the hook has the question text but
not the option list, and guessing which digit means "yes" is the one mistake with
a real blast radius.

So the popup attaches a **second tmux client** to a session grouped with the
target's (`new-session -t`), which is both live and laid out by Claude Code
itself — arrow keys, typing and Escape work with no key table here to get wrong.
Grouped rather than a plain `attach -t` because a group member carries its own
current window, so moving around in the mirror does not repoint the real tab
(verified: outer client stayed on `@0` while the mirror sat on `@1`).

## Leaving is `C-]`, deliberately not a prefix chord

Inside the view you are looking at a pane that may itself hold an ssh session
with its own tmux, and then `C-q` is ambiguous — local tmux, or remote, or
`C-q C-q`? A key needing no prefix cannot be aimed at the wrong tmux.

The cost is that a **root binding is taken from every pane on the server**, so it
has to be a key nothing wants and it has to hand the key back: `C-]` is unbound
in tmux, and outside a view the binding `send-keys` it straight through. `C-o`
and `C-e` were considered and rejected (Claude Code and readline use them;
swallowing those inside the view would be worse than the ambiguity this
replaces).

**The key is advertised only by the view itself** — the border title and the
footer — so `.tmux.conf` and this script are one contract split across two
files. `tmux-agent-view.test.sh` reads the key out of the footer and checks that
`.tmux.conf` binds it. It is named twice on purpose: the footer sits under a
full-screen TUI and is easy to miss, which is exactly how the working view still
drew the question "how do I get back?".

It cannot be advertised in `prefix + ?` at all: **`list-keys -N -T root` returns
nothing even for a root binding that carries a note** (verified on 3.7 —
`list-keys -T root` shows the binding without its note, plain `list-keys -N`
shows it with one, and only the `-T` form is empty, and only for this table;
`-N -T copy-mode-vi` works), so [tmux-cheatsheet](tmux-cheatsheet.md) would have
to join two listings to reach it.

## Session naming and reopening

The `_agent_<window>_<pid>` name puts the mirror under the same `_*` guard that
stops `prefix + p/t/o/a` opening a popup inside a popup — see
[tmux-popup.md](tmux-popup.md). Leaving reopens the picker, so several blocked
agents can be answered in a row.

## The view is inset and bordered

An earlier attempt to make it not resize the window was the wrong trade. tmux
sizes a window to the latest client (`window-size latest`), so a second client
resizes the window it is looking at. That can be avoided exactly — borderless
(`-B`), sized to `#{window_width}` × `#{window_height}` + 1 — and it does work
(verified: an 80x23 window stayed 80x23).

It was still wrong: a popup covering the terminal edge to edge is
indistinguishable from having jumped, and the first report back was "the whole
screen changed". A view you cannot tell you are inside is worse than one costing
a redraw, so the popup is `-w 90% -h 85%` with a border and a `-T` title naming
the agent's window.

**What the resize actually costs was measured, not guessed**: a 62x18 popup took
an 80x23 window to 60x15 and rewrapped its long lines (41 rows of history became
75), and after closing, `capture-pane -S -60` came back **byte-identical** —
tmux reflows back losslessly. So the price is two redraws of a live TUI, not a
damaged transcript.

One caveat found while measuring: the restore only happens when a client is
still attached to that window, which is the real configuration (each WezTerm tab
is a session with its own client) but is *not* what a naive test sets up — a test
where the agent's window has no client of its own shows it stuck at the popup's
size and looks like a bug.

## The footer is a status line, and it is not decoration

The border says "popup" but not how to leave, and no key for that is guessable.
`status on`, `status-position bottom` (the global is `top`, so this must be
explicit or the hint lands above the pane and reads as a title), Everforest
orange — deliberately not the red the blocked states share, since the footer is
a hint and not an alarm — and a **literal** `status-format[0]` — literal
so the bar costs no `#()` fork and never redraws on `status-interval`.

## A popup cannot grow, and a second cannot be stacked

`display-popup` aimed at a client that already has one *modifies* it, with `-w`,
`-h` and the shell-command among the options ignored in that case (tmux(1)) — so
`ctrl-o` would look like a dead key.

The picker's popup is therefore closed with `-C` first, and the reopen is issued
through **`tmux run-shell -b`**, which forks on the tmux *server*: a helper
started from inside the popup would be killed by the very `-C` that has to
precede its own `display-popup`.

That also means `run-shell` runs with the **server's** environment, so neither
script may find the other on `$PATH` — each resolves the other as a sibling of
`$0`, which is why both must be linked into the same directory
(`link_dotfiles()` keeps them adjacent).

## Accepted costs

- The active pane is a property of the window and therefore shared, so opening
  the view moves the real tab's cursor to the agent's pane. Unavoidable — keys
  only reach a pane that is active.
- **Remote agents are not supported here yet**, because the mirror would have to
  be a nested `ssh -t <host> tmux attach` sized to the *remote* window, which
  nothing on this machine exercises.

## Testing (`tmux-agent-view.test.sh`)

Like [tmux-popup.test.sh](tmux-popup.md), and for the same structural reason,
this is checked against a **stubbed** `tmux`: the script's whole job is
`display-popup` plus `attach`, both of which need an attached client with a pty,
which `run-shell` does not have. So the assertions are on the command lines it
decides.

What earns its keep is everything whose absence is silent:

- the popup staying inset and bordered (a stray `-B` or a 100% geometry brings
  back the full-screen view that read as "the whole screen changed");
- the title, and the footer naming the leave key — checked against the binding
  in `.tmux.conf`, since the view is the only place that key is advertised;
- the `-C` *before* the second `display-popup`, without which tmux modifies the
  picker's popup and `ctrl-o` looks like a dead key;
- the `_*` session name that the `.tmux.conf` guard depends on;
- the sweep killing only *unattached* mirrors;
- the reopened list's geometry, which is duplicated in `.tmux.conf` because a
  binding cannot read it from the script.

The stub answers `137x42` deliberately — not round, and not the size of anything
else — so a percentage or a hard-coded geometry cannot pass.

Two cases **do** attach a real pty client, via `script(1)` (whose argument order
differs between BSD and GNU, so both spellings are tried), because they cannot be
reached without one: `display-popup` needs a client, so with none the picker
refuses `ctrl-o` for the wrong reason and a missing state gate looks identical to
a working one. They pin exactly the two things first noticed by eye — that a
non-blocked row attaches nothing and does not jump either, and that the view is
**inset**, asserted by measuring the mirror client against the terminal, since
"the whole screen changed" is a regression no percentage in the source can
express.

One trap found writing it: `display-message -p -c <client> '#{client_width}'`
does **not** report that client while a popup is open — it answered with the
popup's own size, which made the assertion compare the mirror against itself and
pass for the wrong reason. Both sizes are read out of one `list-clients` and
matched by name instead.

**What still needs an eye:** after changing either script, press `prefix + a`,
`ctrl-o` on a blocked agent, and check that the tab you came from stays on its
own window, that `C-]` brings the picker back, and that the agent's pane is back
at its original size afterwards.
