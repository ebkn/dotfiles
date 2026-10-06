#!/usr/bin/env bash
# Tests for .tmux.conf itself, and for the link between it and bin/tmux-cheatsheet.
#
# Nothing here checks behaviour that a person would notice quickly. It checks
# the three ways this config breaks *quietly*:
#
#   1. A syntax error or an unknown option. tmux reports it once, on the client
#      that loads the config, and then carries on with everything after the bad
#      line unapplied. Nobody re-reads the config on a working machine, so the
#      first symptom is a key that stopped working weeks later.
#   2. A `bind` that lost its `-N` note. `tmux list-keys -N` only lists keys
#      that carry one, so bin/tmux-cheatsheet simply does not show it. The
#      binding still works; it just becomes undiscoverable, which is the exact
#      failure the cheatsheet exists to prevent.
#   3. The cheatsheet rendering nothing, or dropping a group. Its own failure
#      modes (an awk subscript slip, a width misread) print an empty or short
#      page and exit 0.
#
# Runs against a throwaway server (-L, its own socket) so it cannot touch the
# real one. Requires tmux and fails rather than skips without it.
#
# Run: bash bin/tmux-conf.test.sh   (exit 0 = pass)
set -uo pipefail
# A tmux suite: container or CI only (see bin/tmux-test-guard.sh).
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux-conf.test: tmux is required" >&2
  exit 1
fi

socket="conf-test-$$"
work=$(mktemp -d)
cleanup() {
  tmux -L "$socket-outer" kill-server 2>/dev/null
  tmux -L "$socket" kill-server 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

failures=0
fail() {
  printf 'FAIL %s\n' "$1"
  shift
  [ $# -gt 0 ] && printf '  %s\n' "$@"
  failures=$((failures + 1))
}
pass() { printf 'ok   %s\n' "$1"; }

# --- 1. the config loads cleanly --------------------------------------------

# The obvious form of this check does not work. `tmux -f ./.tmux.conf
# new-session -d` swallows config errors completely -- exit 0, empty stderr,
# and nothing in `show-messages` -- verified here by feeding it a config
# containing both an unknown option and a `bind` with no arguments. That is the
# same silence a person gets on a real machine, which is why a broken line can
# sit in this file unnoticed.
#
# `source-file` is the form that reports: it prints "<file>:<line>: <error>" on
# stderr AND exits non-zero. So the server starts empty and the config is
# sourced into it, which also leaves it loaded for the checks below.
#
# A FIXTURE $HOME, because the config's last two lines reach into the real one
# and both of them make this case lie:
#
#   run '~/.tmux/plugins/tpm/tpm'
#   run-shell 'f="$HOME/.tmux/plugins/tmux-fzf-url/fzf-url.sh"; ... sed -i ...'
#
# Without the plugin manager installed, tpm exits 127 and `source-file` reports
# that on stderr -- so a perfectly well-formed config fails this case on every
# machine that is not the developer's, which is what turned CI red. Excusing the
# line in the captured stderr was the alternative, and it would have loosened
# "stderr must be empty" for everything else too; that strictness is the entire
# reason source-file is used here rather than `new-session -f`.
#
# The second line is the better argument: on a machine where that plugin IS
# installed, this test rewrites it in place with `sed -i`. A fixture $HOME
# reproduces the precondition and takes the test out of the real one at the same
# time.
#
# Exported before the server starts: tmux expands `~` and `$HOME` from the
# SERVER's environment, not from the client that sources the file.
mkdir -p "$work/home/.tmux/plugins/tpm"
printf '#!/bin/sh\nexit 0\n' >"$work/home/.tmux/plugins/tpm/tpm"
chmod +x "$work/home/.tmux/plugins/tpm/tpm"
export HOME="$work/home"

tmux -L "$socket" -f /dev/null new-session -d
load_err=$(tmux -L "$socket" source-file ./.tmux.conf 2>&1)
load_rc=$?
if [ "$load_rc" -ne 0 ] || [ -n "$load_err" ]; then
  fail ".tmux.conf loads without errors" "exit $load_rc" "$load_err"
else
  pass ".tmux.conf loads without errors"
fi

# --- 2. every prefix binding carries a note ---------------------------------

# Checked against the file rather than the server because the file is what
# someone edits. `-n` binds live in the root table, which neither the cheatsheet
# nor `list-keys -T prefix` shows, so a note there would have no reader.
unnoted=$(grep -nE '^[[:space:]]*(bind|bind-key)[[:space:]]' .tmux.conf |
  grep -v -- ' -n ' |
  grep -v -- ' -N ')
if [ -n "$unnoted" ]; then
  fail "every non-root binding in .tmux.conf has -N" \
    "these are invisible to bin/tmux-cheatsheet:" "$unnoted"
else
  pass "every non-root binding in .tmux.conf has -N"
fi

# Popups are exempt from d's guard: there d closes a popup, which is what it
# looks like it does. Checked as the FIRST branch, because the guard's own cases
# below never run in a popup -- with the branches swapped, every ordinary pane
# would detach at once and only popups would ask. `list-keys -T prefix d`
# returns nothing on 3.7 -- the key argument is not honoured there -- so the
# whole table is listed and the row picked out. The note sits between the table
# and the key, hence the optional group.
d_binding=$(tmux -L "$socket" list-keys -T prefix 2>/dev/null |
  grep -E '^bind-key +(-N "[^"]*" +)?-T prefix +d ' | head -1)
case "$d_binding" in
  *'if-shell -F "#{E:@in_popup}" detach-client '*)
    pass "prefix + d detaches a popup without asking"
    ;;
  *) fail "prefix + d detaches a popup without asking" "got: ${d_binding:-<unbound>}" ;;
esac

# --- 2b. local d/q/F12 ask which machine you meant, in an ssh pane ----------

# In an ssh pane, d / q / F12 act on THIS tmux, not the remote one, and each of
# them ends the ssh session or drops the local client -- a re-login to undo. So
# there they open a menu naming the host instead of a generic y/n, which is easy
# to answer on reflex because it reads the same everywhere.
#
# Asserted on a rendered menu, not on the binding text: what matters is what
# shows up and what each item does, and display-menu drops an item whose name
# expands empty -- the mechanism that hides "remote" on a plain ssh pane -- only
# at draw time. A menu needs a real client, so one is attached from a pane of a
# second, config-free server: keys sent to that pane reach our server as typed,
# and the menu is drawn into it where capture-pane can read it.
#
# The guarded pane runs cat -v with flow control off, so the keys a "remote"
# item sends arrive visibly (^Q would otherwise be eaten as XON) -- standing in
# for the nested tmux that would receive them over ssh.
outer="tmux -L $socket-outer"
probe_cmd="sh -c 'stty -ixon; exec cat -v'"
# By id, not index: the config sets pane-base-index, so `.0` names no pane.
ssh_pane=$(tmux -L "$socket" new-session -d -P -F '#{pane_id}' -s guard -x 100 -y 30 "$probe_cmd")
tmux -L "$socket" set-option -p -t guard: @ssh_host devbox
tmux -L "$socket" set-option -p -t guard: @ssh_my_machine 1
$outer -f /dev/null new-session -d -x 100 -y 30 "env -u TMUX tmux -L $socket attach -t guard"

# Polls: menus and prompts are drawn asynchronously. screen_has is the client's
# view (menus are overlays, not pane content); pane_has is the guarded pane's.
screen_has() {
  local _
  for _ in $(seq 25); do
    $outer capture-pane -p 2>/dev/null | grep -qF -- "$1" && return 0
    sleep 0.2
  done
  return 1
}
screen_lacks() {
  local _
  for _ in $(seq 25); do
    $outer capture-pane -p 2>/dev/null | grep -qF -- "$1" || return 0
    sleep 0.2
  done
  return 1
}
pane_has() {
  local _
  for _ in $(seq 25); do
    tmux -L "$socket" capture-pane -p -t "$1" 2>/dev/null | grep -qF -- "$2" && return 0
    sleep 0.2
  done
  return 1
}
clients() { tmux -L "$socket" list-clients 2>/dev/null | wc -l | tr -d ' '; }
screen() { $outer capture-pane -p 2>/dev/null; }

if screen_has 'SSH: devbox'; then
  pass "a client attaches for the guard cases"
else
  fail "a client attaches for the guard cases" "$(screen)"
fi

# d in a myssh pane: the host is named, and both machines are offered.
$outer send-keys C-q d
if screen_has 'this pane is ssh to devbox' &&
  screen_has 'detach on devbox (remote)' &&
  screen_has 'detach the LOCAL client'; then
  pass "prefix + d in a myssh pane opens a menu naming the host"
else
  fail "prefix + d in a myssh pane opens a menu naming the host" "$(screen)"
fi
# "remote" passes the chord down, and must not detach here.
$outer send-keys r
if pane_has guard: '^Qd' && screen_lacks 'this pane is ssh to' && [ "$(clients)" = 1 ]; then
  pass "the remote item sends C-q d to the pane and keeps this client"
else
  fail "the remote item sends C-q d to the pane and keeps this client" \
    "clients: $(clients)" "$(tmux -L "$socket" capture-pane -p -t guard:)"
fi

# On a plain ssh pane there is no nested tmux to send it to, so no remote item.
tmux -L "$socket" set-option -p -u -t guard: @ssh_my_machine
$outer send-keys C-q d
menu_seen=0
screen_has 'detach the LOCAL client' && menu_seen=1
if [ "$menu_seen" = 1 ] && ! screen | grep -qF '(remote)'; then
  pass "prefix + d in a plain ssh pane offers no remote item"
else
  fail "prefix + d in a plain ssh pane offers no remote item" "$(screen)"
fi
$outer send-keys c
# Gated on the menu having been up, or this passes with no menu at all.
if [ "$menu_seen" = 1 ] && screen_lacks 'detach the LOCAL client' && [ "$(clients)" = 1 ]; then
  pass "cancel closes the menu and detaches nothing"
else
  fail "cancel closes the menu and detaches nothing" "clients: $(clients)" "$(screen)"
fi
tmux -L "$socket" set-option -p -t guard: @ssh_my_machine 1

# q: same menu shape; "remote" sends C-q q down.
$outer send-keys C-q q
if screen_has 'kill the pane on devbox (remote)' && screen_has 'kill this LOCAL pane'; then
  pass "prefix + q in a myssh pane opens a menu naming the host"
else
  fail "prefix + q in a myssh pane opens a menu naming the host" "$(screen)"
fi
$outer send-keys r
if pane_has guard: '^Qq' && tmux -L "$socket" has-session -t guard 2>/dev/null; then
  pass "the remote item sends C-q q to the pane and keeps it"
else
  fail "the remote item sends C-q q to the pane and keeps it" "$(tmux -L "$socket" capture-pane -p -t guard:)"
fi
# Each binding carries its own copy of the cancel item, and a broken one in q
# would kill the very pane the menu exists to protect.
pane_alive() { tmux -L "$socket" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$1"; }
$outer send-keys C-q q
menu_seen=0
screen_has 'kill this LOCAL pane' && menu_seen=1
$outer send-keys c
if [ "$menu_seen" = 1 ] && screen_lacks 'kill this LOCAL pane' && pane_alive "$ssh_pane"; then
  pass "cancel on q's menu keeps the ssh pane"
else
  fail "cancel on q's menu keeps the ssh pane" "$(screen)"
fi

# F12 (Cmd+W): a root key, and it kills the WINDOW, so it guards when any pane
# in the window is ssh -- including one that is not the active pane.
$outer send-keys F12
if screen_has 'close the window on devbox (remote)' && screen_has 'close this LOCAL window'; then
  pass "F12 in a myssh window opens a menu naming the host"
else
  fail "F12 in a myssh window opens a menu naming the host" "$(screen)"
fi
$outer send-keys r
if pane_has guard: '^[[24~' && tmux -L "$socket" has-session -t guard 2>/dev/null; then
  pass "the remote item sends F12 to the pane and keeps the window"
else
  fail "the remote item sends F12 to the pane and keeps the window" "$(tmux -L "$socket" capture-pane -p -t guard:)"
fi
plain_pane=$(tmux -L "$socket" split-window -P -F '#{pane_id}' -t guard: "$probe_cmd")
$outer send-keys F12
menu_seen=0
screen_has 'close this LOCAL window' && menu_seen=1
if [ "$menu_seen" = 1 ] && ! screen | grep -qF '(remote)'; then
  pass "F12 guards a window whose ssh pane is not the active one"
else
  fail "F12 guards a window whose ssh pane is not the active one" "$(screen)"
fi
# Cancel keeps the whole window, both panes of it -- F12 kills windows.
$outer send-keys c
if [ "$menu_seen" = 1 ] && screen_lacks 'close this LOCAL window' &&
  pane_alive "$ssh_pane" && pane_alive "$plain_pane"; then
  pass "cancel on F12's menu keeps the window"
else
  fail "cancel on F12's menu keeps the window" "$(tmux -L "$socket" list-panes -t guard: 2>&1)"
fi

# The LOCAL items still do what the keys always did. The split left the plain
# pane active, so the ssh pane is selected first; killing it leaves the plain
# one for the unguarded cases after.
tmux -L "$socket" select-pane -t "$ssh_pane"
$outer send-keys C-q q
screen_has 'kill this LOCAL pane' >/dev/null
$outer send-keys l
for _ in $(seq 25); do
  tmux -L "$socket" list-panes -t guard: -F '#{pane_id}' 2>/dev/null | grep -qxF "$ssh_pane" || break
  sleep 0.2
done
if ! tmux -L "$socket" list-panes -t guard: -F '#{pane_id}' 2>/dev/null | grep -qxF "$ssh_pane" &&
  tmux -L "$socket" has-session -t guard 2>/dev/null; then
  pass "the LOCAL item of q kills the ssh pane"
else
  fail "the LOCAL item of q kills the ssh pane" "$(tmux -L "$socket" list-panes -t guard: 2>&1)"
fi

# Outside an ssh pane nothing changes: d and q keep their y/n prompts.
$outer send-keys C-q d
if screen_has 'detach this client? (y/n)'; then
  pass "prefix + d in a local pane keeps its y/n prompt"
else
  fail "prefix + d in a local pane keeps its y/n prompt" "$(screen)"
fi
$outer send-keys n
$outer send-keys C-q q
if screen_has 'kill-pane? (y/n)'; then
  pass "prefix + q in a local pane keeps its y/n prompt"
else
  fail "prefix + q in a local pane keeps its y/n prompt" "$(screen)"
fi
$outer send-keys n

# F12's LOCAL item is the most deeply quoted command here -- run-shell inside a
# menu item inside a brace block -- and a quote lost there makes it do nothing,
# silently. A second window keeps the session (and the client) alive after.
window_gone() {
  local _
  for _ in $(seq 25); do
    tmux -L "$socket" list-windows -a -F '#{window_id}' 2>/dev/null | grep -qxF "$1" || return 0
    sleep 0.2
  done
  return 1
}
ssh_window=$(tmux -L "$socket" new-window -P -F '#{window_id}' -t guard: "$probe_cmd")
tmux -L "$socket" set-option -p -t "$ssh_window" @ssh_host devbox
$outer send-keys F12
menu_seen=0
screen_has 'close this LOCAL window' && menu_seen=1
$outer send-keys l
if [ "$menu_seen" = 1 ] && window_gone "$ssh_window"; then
  pass "the LOCAL item of F12 closes the window"
else
  fail "the LOCAL item of F12 closes the window" "$(tmux -L "$socket" list-windows -t guard: 2>&1)"
fi
# And a window with no ssh pane closes on F12 with no menu, as it always did.
plain_window=$(tmux -L "$socket" new-window -P -F '#{window_id}' -t guard: "$probe_cmd")
$outer send-keys F12
if window_gone "$plain_window" && ! screen | grep -qF 'LOCAL tmux'; then
  pass "F12 in a window with no ssh pane closes it without asking"
else
  fail "F12 in a window with no ssh pane closes it without asking" "$(screen)"
fi

# Last, because it ends the client: the LOCAL item of d detaches.
tmux -L "$socket" set-option -p -t guard: @ssh_host devbox
$outer send-keys C-q d
menu_seen=0
screen_has 'detach the LOCAL client' && menu_seen=1
$outer send-keys l
for _ in $(seq 25); do
  [ "$(clients)" = 0 ] && break
  sleep 0.2
done
# Gated on the menu: with none, a client that died for any other reason passes.
if [ "$menu_seen" = 1 ] && [ "$(clients)" = 0 ]; then
  pass "the LOCAL item of d detaches this client"
else
  fail "the LOCAL item of d detaches this client" "clients: $(clients)"
fi
$outer kill-server 2>/dev/null
tmux -L "$socket" kill-session -t guard 2>/dev/null

# "Am I in a popup?" is one option, @in_popup, because bin/tmux-popup and
# bin/tmux-agent-view name their sessions `_...` and eight bindings have to agree
# on what that means: p/t/o/a/A and the command popups g/? refuse to open a
# popup inside one, d skips its confirmation there. Written out per binding it
# was six copies of a glob (g and ? had none at all), and a
# seventh binding copied wrong would stack popups with no error anywhere. So the
# value is checked as a FORMAT, against a popup-named session and an ordinary
# one, and each binding is checked for asking it with the refusal as the TRUE
# branch (d is checked above, the other way round).
tmux -L "$socket" new-session -d -s _popup_probe
tmux -L "$socket" new-session -d -s plain_probe
in_popup=$(tmux -L "$socket" display-message -p -t _popup_probe: '#{E:@in_popup}')
not_popup=$(tmux -L "$socket" display-message -p -t plain_probe: '#{E:@in_popup}')
if [ "$in_popup" = 1 ] && [ "$not_popup" = 0 ]; then
  pass "@in_popup is true in a popup session and false in any other"
else
  fail "@in_popup is true in a popup session and false in any other" \
    "_popup_probe: [$in_popup], plain_probe: [$not_popup]"
fi
tmux -L "$socket" kill-session -t _popup_probe
tmux -L "$socket" kill-session -t plain_probe
prefix_keys=$(tmux -L "$socket" list-keys -T prefix 2>/dev/null)
for k in p t o a A g '?'; do
  # `?` is an ERE operator; every other key here is a literal already.
  key_re=$k
  [ "$k" = '?' ] && key_re='\?'
  row=$(printf '%s\n' "$prefix_keys" |
    grep -E "^bind-key +(-N \"[^\"]*\" +)?-T prefix +$key_re " | head -1)
  case "$row" in
    *'if-shell -F "#{E:@in_popup}" "display-message \"already in a popup\""'*)
      pass "prefix + $k refuses inside a popup, asking @in_popup"
      ;;
    *) fail "prefix + $k refuses inside a popup, asking @in_popup" "got: ${row:-<unbound>}" ;;
  esac
  # g and ? were wrapped in that guard after the fact, their command moved into
  # its else block. That a config loads says nothing about whether the move kept
  # the command intact, so the else block is checked to still open the same thing.
  case $k in
    g) want='gh pr view --web' ;;
    '?') want='tmux-cheatsheet' ;;
    *) continue ;;
  esac
  case "$row" in
    *'already in a popup\"" { display-popup '*"$want"*'}'*)
      pass "prefix + $k still opens its popup outside one"
      ;;
    *) fail "prefix + $k still opens its popup outside one" "want [$want] in the else block" "got: $row" ;;
  esac
done

# C-] is the way out of the answer view, and the footer that advertises it is
# written by bin/tmux-agent-view -- so the binding has to exist here, be guarded
# to the view's own sessions, and live in the ROOT table. A prefix chord would
# be ambiguous inside a view whose pane holds a nested tmux over ssh, which is
# the whole reason it is not one; demoting it back to the prefix table would
# leave the popup advertising a key that does nothing.
#
# Each branch is matched in its place, not as a word anywhere in the row: with
# the branches swapped both words are still there, and C-] would then detach
# the client from every ordinary pane on the server while doing nothing in the
# one view it exists to leave.
leave_binding=$(tmux -L "$socket" list-keys -T root 2>/dev/null |
  grep -E "^bind-key +(-N \"[^\"]*\" +)?-T root +C-\] " | head -1)
case "$leave_binding" in
  *'_agent_*,#{session_name}}" detach-client '*) pass "C-] leaves an agent view, with no prefix" ;;
  *) fail "C-] leaves an agent view, with no prefix" "got: ${leave_binding:-<unbound>}" ;;
esac
# Outside a view the key belongs to whatever is running in the pane: a root
# binding is taken from every pane on the server, so it has to hand it back.
case "$leave_binding" in
  *'" detach-client "send-keys C-]"'*) pass "C-] is passed through outside a view" ;;
  *) fail "C-] is passed through outside a view" "got: $leave_binding" ;;
esac

# And the other direction: the notes must actually reach the server. A note that
# tmux parsed as part of the command instead would pass the grep above.
noted_on_server=$(tmux -L "$socket" list-keys -N -T prefix 2>/dev/null | grep -cE '^[^ ]+ +[a-z][a-z ]*:')
noted_in_file=$(grep -cE '^[[:space:]]*(bind|bind-key)[[:space:]].* -N "[a-z]' .tmux.conf)
if [ "$noted_on_server" -eq 0 ]; then
  fail "tagged notes reach the running server" "list-keys -N -T prefix matched none"
elif [ "$noted_on_server" -lt "$noted_in_file" ]; then
  fail "tagged notes reach the running server" \
    "file has $noted_in_file prefix notes, server reports $noted_on_server"
else
  pass "tagged notes reach the running server ($noted_on_server)"
fi

# --- 3. the swap binding survives tmux's own parser -------------------------

# prefix + w is the one binding here whose body is a two-level quoting puzzle:
# choose-tree's command template is a string inside the binding, and the %%
# substitution inside *that* has to reach bin/tmux-session-swap with its quotes
# intact. bin/tmux-session-swap.test.sh covers the script in thirteen cases, but
# nothing covered the wiring, so the whole feature could stop working with every
# one of those still green.
#
# It fails quietly in both directions. If the arm half is lost, `go` finds no
# recorded tty and degrades to a plain switch -- the mirroring bug the swap
# exists to prevent, back with no message. If the %% escaping is lost, `go`
# receives a target it cannot resolve, `session_of` returns empty, and w simply
# does nothing.
#
# Asserted against the server rather than the file: the file only says what was
# written, and the question is what tmux parsed.
w_binding=$(tmux -L "$socket" list-keys -T prefix 2>/dev/null | grep -E '^bind-key .* w[[:space:]]+run-shell')
case "$w_binding" in
  *"tmux-session-swap arm '#{client_tty}'"*)
    pass "prefix + w arms the swap with the picking client's tty"
    ;;
  *)
    fail "prefix + w arms the swap with the picking client's tty" \
      "the arm half is missing from what tmux parsed:" "${w_binding:-<no w binding found>}"
    ;;
esac
case "$w_binding" in
  *'tmux-session-swap go \"%%\"'*)
    pass "prefix + w passes choose-tree's %% through to the swap"
    ;;
  *)
    fail "prefix + w passes choose-tree's %% through to the swap" \
      "the %% template did not survive parsing:" "${w_binding:-<no w binding found>}"
    ;;
esac

# --- 4. the cheatsheet renders them -----------------------------------------

# --width avoids needing a pty; the real geometry comes from stty.
tmux -L "$socket" run-shell "cd $PWD && PATH=$PWD/bin:\$PATH tmux-cheatsheet --width 120 >$work/wide 2>$work/wide.err"
tmux -L "$socket" run-shell "cd $PWD && PATH=$PWD/bin:\$PATH tmux-cheatsheet --width 40 >$work/narrow 2>$work/narrow.err"
# run-shell is asynchronous; wait for both files rather than sleeping blindly.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$work/wide" ] && [ -s "$work/narrow" ] && break
  sleep 0.2
done

if [ -s "$work/wide" ]; then
  pass "cheatsheet renders at width 120 ($(wc -l <"$work/wide" | tr -d ' ') lines)"
else
  fail "cheatsheet renders at width 120" "empty output; stderr: $(cat "$work/wide.err" 2>/dev/null)"
fi

# Every category tagged in the config must appear as a heading. A group silently
# vanishing is the failure the tag-shape heuristic in tmux-cheatsheet can cause.
missing_groups=""
while IFS= read -r tag; do
  heading=$(printf '%s' "$tag" | tr '[:lower:]' '[:upper:]')
  grep -qF "$heading" "$work/wide" || missing_groups="$missing_groups $tag"
done < <(grep -oE ' -N "[a-z][a-z ]*:' .tmux.conf | sed -E 's/ -N "//; s/:$//' | sort -u)
if [ -n "$missing_groups" ]; then
  fail "every tagged category appears as a heading" "missing:$missing_groups"
else
  pass "every tagged category appears as a heading"
fi

# How many columns the page was packed into. Counted from the heading rows --
# lines made only of capitals and spaces -- because a row carrying two headings
# is two columns by definition. Line length is NOT the measure: an entry whose
# description is longer than the terminal simply does not fit, and the footer is
# a fixed string, so both exceed a narrow width in correct output.
columns() {
  awk '
    /^[[:space:]]*$/ { next }
    { probe = $0; gsub(/[A-Z ]/, "", probe); if (probe != "") next }   # heading rows only
    { n = split($0, f, /   +/); c = 0
      for (i = 1; i <= n; i++) if (f[i] != "") c++
      if (c > max) max = c }
    END { print max + 0 }
  ' "$1"
}

# Narrow must collapse to exactly one column: that is the case the stty width
# measurement exists for. `$(tput cols)` reports a terminfo default of 80 from
# inside a command substitution, which would pack extra columns here.
narrow_cols=$(columns "$work/narrow")
if [ -s "$work/narrow" ] && [ "$narrow_cols" -eq 1 ]; then
  pass "cheatsheet collapses to one column when narrow"
else
  fail "cheatsheet collapses to one column when narrow" "got $narrow_cols column(s)"
fi

# Wide must use more than one, and never more than the three the layout caps at
# on purpose -- width alone would give five or six and split families that
# belong together.
wide_cols=$(columns "$work/wide")
if [ "$wide_cols" -gt 1 ] && [ "$wide_cols" -le 3 ]; then
  pass "cheatsheet packs into 2-3 columns when wide (got $wide_cols)"
else
  fail "cheatsheet packs into 2-3 columns when wide" "got $wide_cols"
fi

if [ "$failures" -ne 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
