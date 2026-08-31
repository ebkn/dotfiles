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

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux-conf.test: tmux is required" >&2
  exit 1
fi

socket="conf-test-$$"
work=$(mktemp -d)
cleanup() { tmux -L "$socket" kill-server 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

failures=0
fail() { printf 'FAIL %s\n' "$1"; shift; [ $# -gt 0 ] && printf '  %s\n' "$@"; failures=$((failures + 1)); }
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
unnoted=$(grep -nE '^[[:space:]]*(bind|bind-key)[[:space:]]' .tmux.conf \
  | grep -v -- ' -n ' \
  | grep -v -- ' -N ')
if [ -n "$unnoted" ]; then
  fail "every non-root binding in .tmux.conf has -N" \
    "these are invisible to bin/tmux-cheatsheet:" "$unnoted"
else
  pass "every non-root binding in .tmux.conf has -N"
fi

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

# --- 3. the cheatsheet renders them -----------------------------------------

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
