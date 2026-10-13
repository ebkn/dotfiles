#!/usr/bin/env bash
# Tests for bin/tmux-popup.
#
# What is worth pinning here is the session NAME, because it is one rule split
# across two files: tmux-popup builds "_<name>_<id>", and the prefix + p/t/o
# bindings in .tmux.conf refuse to open a popup when `#{session_name}` already
# matches `_*`. Break the naming and the guard stops recognising popups, so the
# chord starts stacking a popup on a popup -- with no error anywhere.
#
# Unlike the other tmux scripts here, this one cannot be checked against a real
# throwaway server: its whole job is `tmux new-session -A`, which attaches, and
# attaching from inside a tmux pane is nested attach -- tmux refuses it, and
# `run-shell` has no pty at all ("open terminal failed: not a terminal"). The
# real path needs display-popup, which needs an attached client. So `tmux` is
# replaced by a stub that records its argv: the assertions are on the command
# line the script decides to run, which is the part this script owns. Whether
# tmux can then attach is tmux's business and is unchanged from when this
# command line was written inline in .tmux.conf.
#
# The commands the popups run are tested below it: fzf-nvim with fzf and nvim
# stubbed, and tmux-tig in a pane of a throwaway server, since its pause reads
# one key from a real terminal -- which is also why this suite is guarded even
# though tmux-popup itself only ever meets a stub.
#
# Run: bin/test-in-docker bin/tmux-popup.test.sh   (exit 0 = pass)
set -uo pipefail
# A tmux suite: container or CI only (see bin/tmux-test-guard.sh).
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
script="$PWD/bin/tmux-popup"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/stub" "$work/cwd"
cat >"$work/stub/tmux" <<'STUB'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done
STUB
chmod +x "$work/stub/tmux"

failures=0

# run <TMUX value> <argv...> — run tmux-popup with the stub on PATH, from a
# known cwd, and echo what it asked tmux to do (one argument per line).
run() {
  local tmux_env="$1"
  shift
  (cd "$work/cwd" && PATH="$work/stub:$PATH" TMUX="$tmux_env" "$script" "$@" 2>&1)
}

check() {
  local desc="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "${want//$'\n'/ | }" "${got//$'\n'/ | }"
    failures=$((failures + 1))
  fi
}

# $TMUX is "socket,pid,session-id"; only the session id belongs in the name.
check 'builds the session name from the third TMUX field' \
  "new-session
-A
-s
_popup_7
-c
$work/cwd" \
  "$(run '/tmp/tmux-501/default,1234,7' popup)"

check 'passes a command through to the new session' \
  "new-session
-A
-s
_tig_7
-c
$work/cwd
tmux-tig" \
  "$(run '/tmp/tmux-501/default,1234,7' tig tmux-tig)"

check 'keeps a multi-word command as separate arguments' \
  "new-session
-A
-s
_x_7
-c
$work/cwd
sh
-c
echo hi" \
  "$(run '/tmp/tmux-501/default,1234,7' x sh -c 'echo hi')"

# Two tabs are two tmux sessions, so the ids differ and the popups must not
# collide -- otherwise every tab attaches to the same popup.
name_a=$(run '/tmp/s,1,0' popup | sed -n '4p')
name_b=$(run '/tmp/s,1,1' popup | sed -n '4p')
check 'different tmux sessions get different popup names' 'differ' \
  "$([ "$name_a" != "$name_b" ] && echo differ || echo "same: $name_a")"

# The cross-file half of the contract: .tmux.conf decides "in a popup" once, as
# @in_popup, so every name this produces must match ITS glob or the guard
# silently stops recognising its own popups. Read from the file rather than
# restated here, which would only be a second copy of the rule to drift.
guard_glob=$(sed -n "s/^set -g @in_popup '#{m:\([^,]*\),#{session_name}}'\$/\1/p" .tmux.conf)
check 'the @in_popup glob can be read from .tmux.conf' 'yes' \
  "$([ -n "$guard_glob" ] && echo yes || echo "no @in_popup line found")"
matches_guard=yes
for n in "$name_a" "$name_b" "$(run '/tmp/s,1,7' fzf_nvim | sed -n '4p')"; do
  # shellcheck disable=SC2254 # the glob is the point: it is the guard's pattern
  case "$n" in $guard_glob) ;; *) matches_guard="no: $n" ;; esac
done
check 'every name matches the @in_popup glob in .tmux.conf' 'yes' "$matches_guard"

# Failure modes are worth pinning too: a popup closes the instant its command
# exits, so a silent exit 0 would look exactly like a working chord.
out=$(run '/tmp/s,1,0' 2>&1)
rc=$?
check 'no arguments is a usage error' 'rc=2' "rc=$rc"
case "$out" in *usage*) ;; *)
  printf 'FAIL usage message missing\n  got: %s\n' "$out"
  failures=$((failures + 1))
  ;;
esac

out=$(run '' popup 2>&1)
rc=$?
check 'outside tmux is an error, not an empty session name' 'rc=1' "rc=$rc"
case "$out" in *"not inside tmux"*) ;; *)
  printf 'FAIL missing-TMUX message wrong\n  got: %s\n' "$out"
  failures=$((failures + 1))
  ;;
esac

# --- the commands the popups run: tmux-tig and fzf-nvim ----------------------
# Both used to be verified by hand only. tig, fzf and nvim are stubbed: what is
# pinned is what these scripts do around them.
mkdir -p "$work/tools"
cat >"$work/tools/tig" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >"$TOOLS_LOG/tig.argv"
[ -z "${TIG_FAIL:-}" ] && exit 0
echo 'tig: Not a git repository' >&2
exit "$TIG_FAIL"
STUB
cat >"$work/tools/fzf" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >"$TOOLS_LOG/fzf.argv"
[ -n "${FZF_PICK:-}" ] || exit 130
printf '%s\n' "$FZF_PICK"
STUB
cat >"$work/tools/nvim" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >"$TOOLS_LOG/nvim.argv"
STUB
chmod +x "$work/tools"/*
tools() { (cd "$work/cwd" && PATH="$work/tools:$PATH" TOOLS_LOG="$work" "$@" 2>&1); }

# A tig that succeeds is left alone: no pause, its status, its arguments.
out=$(tools "$PWD/bin/tmux-tig" --all)
rc=$?
check 'tmux-tig: a successful tig exits 0 at once' 'rc=0' "rc=$rc"
check 'tmux-tig: and prints no pause line' '' "$out"
check 'tmux-tig: arguments reach tig' '--all' "$(cat "$work/tig.argv")"

# A failing one must HOLD the popup until one key -- no Enter -- is pressed, and
# then exit with tig's status. That needs a terminal, so it runs in a pane of a
# throwaway server, with remain-on-exit so the status can be read afterwards.
unset TMUX
sock="popup-test-$$"
trap 'tmux -L "$sock" kill-server 2>/dev/null; rm -rf "$work"' EXIT
printf 'set -g remain-on-exit on\n' >"$work/tmux.conf"
tmux -L "$sock" -f "$work/tmux.conf" new-session -d -s tig -x 100 -y 20 -c "$work/cwd" \
  "PATH='$work/tools':\$PATH TOOLS_LOG='$work' TIG_FAIL=3 '$PWD/bin/tmux-tig'"
pane_text() { tmux -L "$sock" capture-pane -p -t tig: 2>/dev/null; }
pane_dead() { tmux -L "$sock" display-message -p -t tig: '#{pane_dead}' 2>/dev/null; }
for _ in $(seq 1 50); do
  case "$(pane_text)" in *'Press any key'*) break ;; esac
  sleep 0.1
done
screen=$(pane_text)
case "$screen" in
  *'tig: Not a git repository'*'tig exited with status 3. Press any key to close.'*)
    printf 'ok   tmux-tig: a failing tig leaves its message and a pause line on screen\n'
    ;;
  *)
    printf 'FAIL tmux-tig: a failing tig leaves its message and a pause line on screen\n  screen: %s\n' "$screen"
    failures=$((failures + 1))
    ;;
esac
# Still alive after a pause: the popup must not vanish on its own.
sleep 0.5
check 'tmux-tig: the pane waits instead of closing' '0' "$(pane_dead)"
tmux -L "$sock" send-keys -t tig: x
for _ in $(seq 1 50); do
  [ "$(pane_dead)" = 1 ] && break
  sleep 0.1
done
check 'tmux-tig: one key, no Enter, closes it' '1' "$(pane_dead)"
check "tmux-tig: and it exits with tig's status" '3' \
  "$(tmux -L "$sock" display-message -p -t tig: '#{pane_dead_status}' 2>/dev/null)"
tmux -L "$sock" kill-server 2>/dev/null

# fzf-nvim: the picked path is opened, after `--`, so a file named like an
# option is still a file.
out=$(FZF_PICK='-weird name.txt' tools "$PWD/bin/fzf-nvim")
check 'fzf-nvim: the picked file is opened, after --' '--
-weird name.txt' "$(cat "$work/nvim.argv")"
# The preview reads the LAST tab-separated field: the list may carry a hidden
# label column (FZF_DEFAULT_OPTS sets --delimiter=\t --nth=-1).
case "$(cat "$work/fzf.argv")" in
  *'{-1}'*) printf 'ok   fzf-nvim: the preview reads the last field\n' ;;
  *)
    printf 'FAIL fzf-nvim: the preview reads the last field\n  fzf argv: %s\n' "$(cat "$work/fzf.argv")"
    failures=$((failures + 1))
    ;;
esac
# Cancelling still opens nvim: the popup closes the moment its command exits,
# so returning early would look like the chord had failed.
rm -f "$work/nvim.argv"
out=$(FZF_PICK='' tools "$PWD/bin/fzf-nvim")
check 'fzf-nvim: cancelling still opens nvim' 'ran' \
  "$([ -f "$work/nvim.argv" ] && echo ran || echo 'nvim never ran')"
# (The stub prints one line per argument, so no arguments is one empty line.)
check 'fzf-nvim: with no file' '' "$(cat "$work/nvim.argv" 2>/dev/null)"

if [ "$failures" -ne 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
