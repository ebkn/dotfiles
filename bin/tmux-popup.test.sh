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
# Run: bash bin/tmux-popup.test.sh   (exit 0 = pass)
set -uo pipefail

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

# The cross-file half of the contract: .tmux.conf guards with `#{m:_*,...}`, so
# every name this produces must match that glob or the guard silently stops
# recognising its own popups.
matches_guard=yes
for n in "$name_a" "$name_b" "$(run '/tmp/s,1,7' fzf_nvim | sed -n '4p')"; do
  case "$n" in _*) ;; *) matches_guard="no: $n" ;; esac
done
check 'every name matches the _* guard in .tmux.conf' 'yes' "$matches_guard"

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

if [ "$failures" -ne 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
