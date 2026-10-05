# tmux-restore-tabs

Re-opens one WezTerm tab per unattached tmux session, oldest first, after WezTerm
died while tmux survived. Popup sessions (`_*`, from `tmux-popup` and
`tmux-agent-view`) are skipped: they outlive their popup unattached but never had
a tab, and restoring one opened a tab on a popup's shell. A server holding only
popups reports nothing to restore. For the case where the *remote* sessions survived
instead, see [tmux-restore-ssh-tabs.md](tmux-restore-ssh-tabs.md).

## Which pane is "here"

Tabs go into the window the script was run from, and focus returns to the pane
it was run from. The pane is the `focused_pane_id` of the GUI client from
`wezterm cli list-clients` that has been idle the shortest time, i.e. the one the
command was just typed into. The two obvious sources are both wrong, and both
were live bugs:

- **`$WEZTERM_PANE`** is what `wezterm cli spawn` reads when given no
  `--pane-id`. Inside tmux it comes from whatever environment the tmux server
  started with. After WezTerm restarts it names a pane of the *previous*
  WezTerm, and **every restored tab opened in a new window of its own**. With
  continuum restoring ~28 sessions, that looked like an endless stream of
  windows.
- **`is_active` in `wezterm cli list`** is per *tab*: every tab reports one
  active pane (measured: 30+ true entries), so the old query yielded a list of
  ids and `activate-pane` failed.

## Session names are cut by position

The listing is `<created> <name>`, and the name is everything after the first
space. The old `awk` found the name with `index($0, $3)`, the name's *first*
occurrence on the line. For a numeric name that can be inside the timestamp:
`1790660355 0 35` yielded `355 0 35`. Continuum-restored sessions have exactly
such names. The attach target is also `=name`, an exact match rather than a
prefix.

## Testing (`tmux-restore-tabs.test.sh`)

Runs in Docker only (`bin/test-in-docker`, see
[test-in-docker.md](test-in-docker.md)). A real tmux server with a stub
`wezterm`. `$WEZTERM_PANE` is set to a stale value the script must ignore. The
regression name is built from three digits of the session's own
`session_created`, so it occurs inside the timestamp on every run, and a harness
case says so if it does not. Confirmed red against the pre-fix script on the
name, window and focus cases.
