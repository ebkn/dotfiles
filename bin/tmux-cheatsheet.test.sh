#!/bin/bash
#
# tmux-cheatsheet.test.sh
#
# Pins the rendered page, row by row, against a fixture config. Every way the
# cheatsheet breaks prints a plausible page and exits 0: a key column parsed
# one token off shows a chord that does not work, a copy-mode row keeping the
# prefix teaches `C-q y` for a key reached without C-q, a lost sort puts
# "focus left, grow left, focus down" back together, and a heuristic slip
# shows tmux's own ~85 keys or drops a group. bin/tmux-conf.test.sh runs the
# cheatsheet against the real .tmux.conf and checks headings and column count;
# what it cannot pin is the rows themselves, because those change every time a
# binding is added. Hence a fixture whose page can be written out in full.
#
# Real throwaway server: the input is `tmux list-keys -N`, whose format quirks
# (the prefix prepended to every table, notes on tmux's own prefix keys only)
# are the thing a stub would freeze. Isolated by TMUX_TMPDIR with TMUX unset,
# like the other tmux suites. --width supplies the geometry, so no pty is
# needed; PAGER=cat stands in for less when the page is taller than the
# terminal tput falls back to.

set -u
# A tmux suite: container or CI only (see bin/tmux-test-guard.sh).
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2

DIR=$(mktemp -d)
export TMUX_TMPDIR="$DIR/tmux"
unset TMUX TMUX_PANE
mkdir -p "$TMUX_TMPDIR"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/tmux-cheatsheet"
fails=0
cleanup() {
  tmux kill-server 2>/dev/null
  rm -rf "$DIR"
}
trap cleanup EXIT

command -v tmux >/dev/null || {
  echo "tmux is required" >&2
  exit 1
}

t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected:\n%s\n       actual:\n%s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# Each binding is chosen for one trap:
#   - h/j/H/J: the resize keys are the shifted focus keys, so key order alone
#     interleaves the two actions and full-description order scrambles h/j.
#   - session and pane are bound in the reverse of their reading order.
#   - "open github" is a category with a space in it.
#   - zeta and yak are in no reading order: they must still appear, last, and
#     in name order between themselves. Their verbs interleave (alpha, beta,
#     gamma, last), so a sort that lost the category key would mix the two
#     groups and print one heading twice.
#   - X carries an untagged, sentence-case note, which is how tmux's own notes
#     look: it belongs to --all only.
#   - y is in copy-mode-vi, whose rows tmux also prints with the prefix. v is
#     there because it has to be: `list-keys -N -T <table>` prints NOTHING for
#     a table holding exactly one noted key (measured on 3.7c), so a lone y
#     would make the group vanish for a reason that is tmux's, not the script's.
cat >"$DIR/tmux.conf" <<'CONF'
set -g prefix C-q
bind -N "zeta: last thing" Z display-message z
bind -N "zeta: beta two" 3 display-message 3
bind -N "yak: gamma three" 2 display-message 2
bind -N "yak: alpha one" 1 display-message 1
bind -N "pane: grow down" J resize-pane -D
bind -N "pane: grow left" H resize-pane -L
bind -N "pane: focus down" j select-pane -D
bind -N "pane: focus left" h select-pane -L
bind -N "agents: pick an agent" a display-message a
bind -N "open github: open the repository" G display-message g
bind -N "session: new session" N new-session
bind -N "Untagged sentence-case note" X display-message x
bind -T copy-mode-vi -N "yank the selection" y send-keys -X copy-selection
bind -T copy-mode-vi -N "start a selection" v send-keys -X begin-selection
CONF
tmux -f "$DIR/tmux.conf" new-session -d 'sleep 600'

# render [args] -- the page as drawn, column padding and all, with three things
# taken off that belong to the environment rather than the fixture: the
# frame's left margin common to every line (it centres on the width given),
# the leading blank lines of its top margin (capped by the terminal height),
# and the closing hint (shown only when the page fits that height, which is
# whatever tput falls back to). The margin is stripped as ONE amount, so a frame
# that centred line by line would still show as ragged rows.
render() {
  PAGER=cat "$SCRIPT" "$@" </dev/null 2>&1 |
    awk '/^ *\(any key to close\)$/ { next }
         NF { seen = 1 }
         seen { l[++n] = $0 }
         END {
           while (n > 0 && l[n] == "") n--
           m = -1
           for (i = 1; i <= n; i++) if (l[i] != "") {
             match(l[i], /^ */); if (m < 0 || RLENGTH < m) m = RLENGTH
           }
           for (i = 1; i <= n; i++) print substr(l[i], m + 1)
         }'
}
# squash -- single-space the columns, for asserting on one row's content.
squash() { sed -E 's/^ +//; s/ {2,}/ /g'; }

# Narrow, so the page is one column and reads top to bottom: the group order,
# the row order inside each group, and the key column, prefix and all.
expected=$(
  cat <<'PAGE'
SESSION
  C-q N  new session

PANE
  C-q h  focus left
  C-q j  focus down
  C-q H  grow left
  C-q J  grow down

COPY-MODE
  v      start a selection
  y      yank the selection

OPEN GITHUB
  C-q G  open the repository

AGENTS
  C-q a  pick an agent

YAK
  C-q 1  alpha one
  C-q 2  gamma three

ZETA
  C-q 3  beta two
  C-q Z  last thing

all tmux keys: C-q :list-keys -N     describe one key: C-q /
PAGE
)
t "narrow: one column, groups in reading order, rows verb-then-key, prefix only on prefix rows" \
  "$expected" "$(render --width 40)"

# Wide enough for three columns. Each group stays whole in one column, the
# columns fill down then across in reading order, every column is as wide as
# its own widest row, and the grid is centred as one block -- a frame centring
# line by line would leave these rows ragged after the common margin is gone.
wide=$(
  cat <<'PAGE'
SESSION                 COPY-MODE                       YAK
  C-q N  new session      v      start a selection        C-q 1  alpha one
                          y      yank the selection       C-q 2  gamma three
PANE
  C-q h  focus left     OPEN GITHUB                     ZETA
  C-q j  focus down       C-q G  open the repository      C-q 3  beta two
  C-q H  grow left                                        C-q Z  last thing
  C-q J  grow down      AGENTS
                          C-q a  pick an agent

all tmux keys: C-q :list-keys -N     describe one key: C-q /
PAGE
)
t "wide: whole groups packed down then across into three columns" "$wide" "$(render --width 100)"
# Width alone would give five or six columns here; three is the ceiling, so
# the families stay together however wide the popup.
t "very wide: still three columns, the same grid" "$wide" "$(render --width 500)"

# --all adds tmux's own notes, and the untagged one, under a TMUX heading -- the
# last of the reading order, though categories outside the order still sort
# after it. The footer pointing at list-keys goes, since the page now is that
# list.
all=$(render --all --width 40 | squash)
t "--all: tmux's own keys get a TMUX group, at the end of the reading order" \
  "SESSION PANE COPY-MODE OPEN GITHUB AGENTS TMUX YAK ZETA" \
  "$(printf '%s\n' "$all" | grep -E '^[A-Z][A-Z -]*$' | tr '\n' ' ' | sed 's/ $//')"
t "--all: an untagged note is listed under TMUX" "C-q X Untagged sentence-case note" \
  "$(printf '%s\n' "$all" | sed -n '/^TMUX$/,/^$/p' | grep -F 'C-q X ')"
t "--all: a tagged note is not listed again under TMUX" "" \
  "$(printf '%s\n' "$all" | sed -n '/^TMUX$/,/^$/p' | grep -F 'C-q h ')"
t "--all: no footer pointing at the full list" "" \
  "$(printf '%s\n' "$all" | grep -F 'all tmux keys')"

# usage <name> <args...> -- a bad command line prints the usage and exits 2.
usage() {
  local name=$1 out rc
  shift
  out=$("$SCRIPT" "$@" </dev/null 2>&1 >/dev/null)
  rc=$?
  t "$name: exits 2" "2" "$rc"
  t "$name: prints the usage" "usage: tmux-cheatsheet [--all] [--width N]" "$out"
}
usage "an unknown option" --bogus
usage "--width with no value" --width
usage "--width with a non-number" --width wide

# Nothing annotated: say so, rather than print an empty page that looks like a
# broken one.
tmux unbind-key -a -T prefix
tmux unbind-key -a -T copy-mode-vi
t "no annotated bindings: says how to add one" \
  "  (no annotated bindings -- add -N notes in .tmux.conf)" \
  "$(render --width 40 | head -1)"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
