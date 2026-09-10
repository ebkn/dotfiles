# tmux-cheatsheet

Annotated key bindings, grouped into columns. Bound to `prefix + ?`.

## The list is derived, never hand-maintained

It comes from the running tmux server via `tmux list-keys -N`. That inverts where
a binding gets documented: adding `-N "<category>: <description>"` (the category
is lowercase and may contain spaces) to a `bind` line in `.tmux.conf` is the
single act that both describes the key and puts it in the popup, so the two
cannot drift.

**A binding without a note is invisible to the cheatsheet — that is the intended
pressure.** `bin/tmux-conf.test.sh` asserts that every non-`-n` binding carries
`-N`.

The tag becomes the group heading, and the page is laid out as category groups
packed into columns, centred in the popup as one unit. Padding the grid per line
would let the footer drift to its own centre; the top margin is capped, since a
page a third the height of the popup floats with nothing to anchor the eye if
truly centred.

tmux's own ~85 prefix keys are **excluded** unless `--all` is passed, because
they are what made a single list unreadable and are not what gets forgotten; the
footer points at `C-q :list-keys -N` instead.

## Four traps, all verified and all silent when wrong

1. **`$(tput cols)` reports 80 inside the popup.** tput measures the terminal on
   its stdout, and command substitution makes that a pipe, so it falls back to
   the terminfo entry and exits 0 — collapsing the grid to the one column the
   layout exists to avoid. `stty size </dev/tty` is the reading to trust, and
   `--width N` exists so the packing can be checked without a pty.
2. **`list-keys -N` lists only keys that carry a note**, and tmux ships notes on
   its own prefix keys but on **no other table** (`list-keys -N -T copy-mode-vi`
   is empty on a stock server). Hence separating ours by the `<tag>:` + space shape of
   the note — a heuristic whose worst case is a wrong heading. It holds because
   tmux's own notes are sentence-case, so the leading lowercase letter alone
   rules them out. The order list is comma-separated for the same reason a
   category may contain a space.
3. **tmux prepends the prefix key to every line of every table**, so a copy-mode
   binding prints as `C-q y` even though C-q has nothing to do with reaching it.
   The script drops that token for non-prefix tables, since keeping it would
   teach a key that does not work.
4. **In the one true awk (`/usr/bin/awk`), `arr[col SUBSEP ++used]` parses as
   `SUBSEP++ used`**, so the counter never advances and the page renders
   **empty**. Increment on its own statement and subscript with a comma.

## Ordering is imposed, not inherited

`list-keys` emits tmux's key order, which says nothing about how anything reads.

Groups follow an explicit reading order in the script, paired with a hard
three-column ceiling: width alone gives five or six columns on a wide popup and
splits families that belong together (`session` from `pane`, `copy` from
`copy-mode`) purely because a column filled up. Alphabetical, the obvious
default, opens on `agents` and buries `pane`, the group holding half the
bindings. A category missing from the order list still appears, sorted to the
end, so ordering degrades but nothing disappears.

Within a group, entries sort by the description's **leading verb**, then by key.
Sorting by key alone interleaves two different actions (`focus left`,
`grow left`, `focus down`…) because the resize keys are the shifted focus keys,
and sorting by the whole description turns `h/j/k/l` into `focus down, focus
left, focus right, focus up`.

Columns are filled in that reading order and are deliberately **not** levelled:
evening them out would mean reordering or splitting groups, and the order is the
point. The height limit starts at the tallest group (the page can never be
shorter, as a group is never split) and grows until the columns both fit the
width and stop exceeding the ceiling — a taller limit means fewer columns, so it
terminates at one.

## Safety

The popup is display-only by construction (it runs `tmux list-keys` and nothing
else): a list you open to remember "how do I kill this pane" must not kill the
pane.

It is **not** guarded against nesting the way `prefix + p/t/o/a` are, since it
opens no tmux session and mutates nothing.

## Testing

Verified by running it against a throwaway tmux server
(`tmux -L <name> -f ./.tmux.conf new-session -d`), the same isolation
`agent-state.test.sh` uses, with `TMUX` pointed at that socket and the width
supplied by `--width N` — a pty is otherwise required, since the real geometry
comes from `stty`.

**Assert on the rendered grid, not the exit status.** Every failure mode here is
silent: a `bind` line that lost its `-N` note simply vanishes, a mis-parsed key
column shows a wrong-but-plausible chord, an awk subscript slip prints nothing at
all, and a `set -e` slip does the same.

Check a wide width (expect several columns of roughly equal height), a narrow one
(expect one), and `--all`.

Geometry itself cannot be checked this way: confirm it in a real popup with
`tmux display-popup -E -w 90% -h 70% "sh -c 'stty size >/abs/path'"`.
