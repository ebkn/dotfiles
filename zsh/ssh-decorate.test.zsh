#!/usr/bin/env zsh
# Tests for the pane decoration in zsh/ssh.zsh.
#
# The `ssh` and `myssh` wrappers mark the pane while a connection is open and
# put it back afterwards. What they publish is a contract other things read:
# @ssh_host drives the status bar, the purple pane border and which local pane
# bin/tmux-agents jumps to for a given host; @ssh_my_machine is what makes
# .tmux.conf pass prefix + p/t/o/u through to the nested remote tmux instead of
# opening a local popup.
#
# The failure that matters is asymmetry -- something set on the way in and not
# cleared on the way out. A pane left carrying @ssh_host stays purple and keeps
# claiming a host that is no longer connected, and one left carrying
# @ssh_my_machine swallows prefix + p forever, sending it to a remote tmux that
# is not there. Neither produces an error.
#
# The wrappers themselves only get their pass-through checked here: with stdout
# a pipe they set `decorate=false` and skip the pane work entirely (deliberately
# -- see the comment on `decorate` in ssh.zsh), so a test that captures output
# cannot exercise that path through them. The helpers are called directly
# instead, which is also the level the contract lives at.
#
# Run: zsh zsh/ssh-decorate.test.zsh   (exit 0 = pass)

set -u

source "${0:A:h}/ssh.zsh"

typeset -i failures=0
pass() { printf 'ok   %s\n' "$1" }
fail() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; printf '  %s\n' "$l"; (( failures++ )) }

work=$(mktemp -d)
trap 'command rm -rf "$work"' EXIT
mkdir -p "$work/stub"

# tmux and tmux-pane-titles are stubs here: the assertion is on the calls the
# helpers decide to make. What tmux does with a pane option is pinned by the
# tmux-side tests (bin/tmux-pane-titles.test.sh, bin/tmux-agents.test.sh).
cat >"$work/stub/tmux" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$CALLS"
STUB
cat >"$work/stub/tmux-pane-titles" <<'STUB'
#!/bin/sh
printf 'tmux-pane-titles\n' >>"$CALLS"
STUB
cat >"$work/stub/ssh" <<'STUB'
#!/bin/sh
printf 'ssh %s\n' "$*" >>"$CALLS"
exit "${SSH_EXIT:-0}"
STUB
chmod +x "$work/stub"/*
export CALLS="$work/calls"

calls_of() {  # calls_of <TMUX value> <function> [args...] — echo the recorded calls
  local tmux_env=$1
  shift
  : >"$CALLS"
  (
    PATH="$work/stub:$PATH"
    rehash
    TMUX="$tmux_env" "$@" >/dev/null 2>&1
  )
  cat "$CALLS"
}

check() {
  local desc=$1 want=$2 got=$3
  if [[ "$got" == "$want" ]]; then
    pass "$desc"
  else
    fail "$desc" "want: ${want//$'\n'/ | }" "got : ${got//$'\n'/ | }"
  fi
}

inside=/tmp/tmux-501/default,123,0

# --- decorate on -------------------------------------------------------------

check 'marks the pane with the host' \
  "select-pane -P bg=#1e2326
set-option -p @ssh_host myhost
tmux-pane-titles" \
  "$(calls_of "$inside" _ssh_decorate_on myhost)"

# A host the parser could not find must still produce a marked pane, or the
# pane is left looking local while a connection is open.
check 'an unknown host still marks the pane' \
  "select-pane -P bg=#1e2326
set-option -p @ssh_host unknown
tmux-pane-titles" \
  "$(calls_of "$inside" _ssh_decorate_on '')"

check 'my-machine adds @ssh_my_machine' \
  "select-pane -P bg=#1e2326
set-option -p @ssh_host myhost
set-option -p @ssh_my_machine 1
tmux-pane-titles" \
  "$(calls_of "$inside" _ssh_decorate_on myhost 1)"

# Plain ssh must NOT claim the remote runs these dotfiles: that option is what
# sends prefix + p to a nested tmux, and on a jump box there is none.
check 'plain ssh does not set @ssh_my_machine' '' \
  "$(calls_of "$inside" _ssh_decorate_on myhost | grep 'my_machine')"

# --- decorate off ------------------------------------------------------------

# Everything _on can set is cleared, including @ssh_my_machine on the path that
# never set it -- unsetting an unset user option is a silent no-op, and clearing
# both is what makes this the exact inverse.
check 'clears both options and restores the pane' \
  "select-pane -P default
set-option -p -u @ssh_host
set-option -p -u @ssh_my_machine
tmux-pane-titles" \
  "$(calls_of "$inside" _ssh_decorate_off)"

# The symmetry stated as one assertion: every option _on touches, _off unsets.
on_opts=$(calls_of "$inside" _ssh_decorate_on myhost 1 | sed -n 's/^set-option -p \(@[a-z_]*\).*/\1/p' | sort)
off_opts=$(calls_of "$inside" _ssh_decorate_off | sed -n 's/^set-option -p -u \(@[a-z_]*\).*/\1/p' | sort)
check 'every option set on the way in is cleared on the way out' "$on_opts" "$off_opts"

# --- outside tmux ------------------------------------------------------------

check 'outside tmux nothing is published' '' "$(calls_of '' _ssh_decorate_on myhost 1)"

# ...but the terminal reset still happens, because a remote tmux can leave mouse
# tracking on whether or not there is a local tmux.
reset_seq=$(PATH="$work/stub:$PATH" TMUX= _ssh_decorate_off 2>/dev/null | od -c | head -2)
case "$reset_seq" in
  *'?'*'9'*'l'*) pass 'outside tmux the terminal is still reset' ;;
  *) fail 'outside tmux the terminal is still reset' "$reset_seq" ;;
esac

# --- the wrappers still delegate ---------------------------------------------

# Not a tty here, so decorate is false and no pane work happens; what is checked
# is that the refactor left the argv and the exit status alone.
check 'ssh passes its arguments through untouched' \
  'ssh -p 2222 myhost uptime' \
  "$(calls_of "$inside" ssh -p 2222 myhost uptime)"

( PATH="$work/stub:$PATH"; rehash; SSH_EXIT=42 ssh myhost >/dev/null 2>&1 )
check 'ssh returns the exit status of the real ssh' '42' "$?"

# myssh with a remote command never uses autossh, so it falls back to plain ssh.
check 'myssh with a remote command falls back to plain ssh' \
  'ssh myhost uptime' \
  "$(calls_of "$inside" myssh myhost uptime)"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
