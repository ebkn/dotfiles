#!/usr/bin/env bash
# Tests for bin/tmux-pane-titles — the WezTerm tab label.
#
# It reads four pane options per pane and folds them into one window name. The
# whole thing is a labelling decision, so every mistake produces a plausible
# tab title rather than an error: the wrong precedence shows a directory where a
# branch was meant, a broken dedup repeats a label, and a broken strip_type
# spends tab width on "feature/". Nobody notices for weeks.
#
# Runs against a throwaway server, which is the real contract: the script's
# input is tmux pane options and its output is the window name, so a stubbed
# tmux would keep passing if tmux changed what `set-option -p` means.
#
# Requires tmux; fails rather than skips without it.
#
# Run: bash bin/tmux-pane-titles.test.sh   (exit 0 = pass)
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux-pane-titles.test: tmux is required" >&2
  exit 1
fi

socket="titles-test-$$"
work=$(mktemp -d)
cleanup() { tmux -L "$socket" kill-server 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; do printf '  %s\n' "$l"; done; failures=$((failures + 1)); }

mkdir -p "$work/alpha" "$work/bravo" "$work/alpha-again"

# Every pane runs `sleep`, never a shell, and that is not a detail. The shell
# these dotfiles install sources zsh/directory.zsh, whose precmd hook calls
# `tmux set-option -p @git_branch ''` whenever the pane is not in a git
# repository -- which is exactly what these temp directories are. Let a real
# shell start in the pane and it wipes the options the test just set, some
# hundreds of milliseconds later, so the assertions fail intermittently and
# look like the script ignoring pane options.
IDLE='sleep 300'
tmux -L "$socket" -f /dev/null new-session -d -s t -c "$work/alpha" "$IDLE"

# new_window <dir> — start a window, return its id. Each case gets its own
# window so the panes of one do not leak into the next.
#
# The id, not a name: a counter incremented here would be lost, because this
# runs inside a command substitution and so in a subshell. Every window would
# then be called the same thing, tmux permits that, and `-t <name>` silently
# resolves to the first match -- so every case would act on the first window's
# panes and the failures would look like the script ignoring pane options.
new_window() {
  tmux -L "$socket" new-window -t t -c "$1" -P -F '#{window_id}' "$IDLE"
}
add_pane() { # add_pane <target> <dir> [opt=value ...]
  local target=$1 dir=$2 pane
  shift 2
  tmux -L "$socket" split-window -t "$target" -c "$dir" "$IDLE"
  pane=$(tmux -L "$socket" list-panes -t "$target" -F '#{pane_id}' | tail -1)
  local kv
  for kv in "$@"; do
    tmux -L "$socket" set-option -p -t "$pane" "${kv%%=*}" "${kv#*=}"
  done
}
set_opts() { # set_opts <target> <pane index> <opt=value ...>
  local target=$1 idx=$2 pane kv
  shift 2
  pane=$(tmux -L "$socket" list-panes -t "$target" -F '#{pane_id}' | sed -n "$((idx + 1))p")
  for kv in "$@"; do
    tmux -L "$socket" set-option -p -t "$pane" "${kv%%=*}" "${kv#*=}"
  done
}

title_of() { # title_of <window id> — run the script there, echo the resulting name
  local target=$1 before after
  before=$(tmux -L "$socket" display-message -p -t "$target" '#{window_name}')
  # run-shell is asynchronous, so poll for the rename rather than sleeping once.
  tmux -L "$socket" run-shell -t "$target" "$PWD/bin/tmux-pane-titles"
  after=$before
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.15
    after=$(tmux -L "$socket" display-message -p -t "$target" '#{window_name}')
    [ "$after" != "$before" ] && break
  done
  printf '%s' "$after"
}

check() {
  local desc=$1 want=$2 got=$3
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc" "want [$want]" "got  [$got]"; fi
}

# --- directory basenames -----------------------------------------------------

t1=$(new_window "$work/alpha")
add_pane "$t1" "$work/bravo"
check 'joins the panes directory basenames' 'alpha,bravo' "$(title_of "$t1")"

# Two panes in the same directory are one label, not two: the tab is short and a
# repeated word tells you nothing.
t2=$(new_window "$work/alpha")
add_pane "$t2" "$work/alpha"
check 'collapses panes that share a label' 'alpha' "$(title_of "$t2")"

# --- branch and worktree labels ---------------------------------------------

t3=$(new_window "$work/alpha")
set_opts "$t3" 0 '@git_branch=fix/the-thing'
check 'a branch is shown as b: with the type prefix dropped' 'b:/the-thing' "$(title_of "$t3")"

t4=$(new_window "$work/alpha")
set_opts "$t4" 0 '@git_worktree=feature/big'
check 'a worktree is shown as w: with the type prefix dropped' 'w:/big' "$(title_of "$t4")"

# A name with no "/" has no type to drop and must survive intact.
t5=$(new_window "$work/alpha")
set_opts "$t5" 0 '@git_branch=hotfix'
check 'a branch with no / is left alone' 'b:hotfix' "$(title_of "$t5")"

# --- precedence --------------------------------------------------------------

# ssh wins over everything: the pane is somewhere else, which is the one fact
# worth the tab width. Then worktree, then branch, then the directory.
t6=$(new_window "$work/alpha")
set_opts "$t6" 0 '@ssh_host=somehost' '@git_worktree=feature/x' '@git_branch=feature/y'
check 'ssh outranks worktree and branch' '≫' "$(title_of "$t6")"

t7=$(new_window "$work/alpha")
set_opts "$t7" 0 '@git_worktree=feature/x' '@git_branch=feature/y'
check 'worktree outranks branch' 'w:/x' "$(title_of "$t7")"

# --- mixed -------------------------------------------------------------------

# The realistic shape: one local worktree pane and one ssh pane, in order.
t8=$(new_window "$work/alpha")
set_opts "$t8" 0 '@git_branch=fix/local'
add_pane "$t8" "$work/bravo" '@ssh_host=remote1'
check 'mixes labels of different kinds in pane order' 'b:/local,≫' "$(title_of "$t8")"

# Several ssh panes collapse to one marker, since the host name is not shown.
t9=$(new_window "$work/alpha")
set_opts "$t9" 0 '@ssh_host=remote1'
add_pane "$t9" "$work/bravo" '@ssh_host=remote2'
check 'several ssh panes collapse to one marker' '≫' "$(title_of "$t9")"

if [ "$failures" -ne 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
