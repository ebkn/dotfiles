#!/usr/bin/env zsh
# Tests for which remote tmux session `myssh` attaches to.
#
# By default the session is named after the local pane (local-<pane id>), so
# each pane keeps its own remote session. bin/tmux-restore-ssh-tabs needs to
# name it instead: a restored tab is a new pane, and connecting under its own
# pane id would open a fresh, empty session beside the one being restored --
# silently, since new-session -A creates what it does not find.
#
# The contract is the argument tmux-track-session receives on the remote, so
# the remote command autossh is handed is run through sh here, against a stub
# tmux-track-session, exactly as the remote login shell would run it. Asserting
# on the command's text instead would pass a name with a space that the remote
# shell then splits in two.
#
# Run: zsh zsh/ssh-session.test.zsh   (exit 0 = pass)

set -u

source "${0:A:h}/ssh.zsh"

typeset -i failures=0
pass() { printf 'ok   %s\n' "$1" }
fail() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; printf '  %s\n' "$l"; (( failures++ )) }

work=$(mktemp -d)
trap 'command rm -rf "$work"' EXIT
mkdir -p "$work/stub" "$work/home/.local/bin"

# autossh keeps only the remote command (its last argument). ssh answers the
# `ssh -G` hostname lookup with nothing, so no keepalive ping is started.
cat >"$work/stub/autossh" <<'STUB'
#!/bin/sh
for a; do last=$a; done
printf '%s' "$last" >"$REMOTE"
STUB
cat >"$work/stub/ssh" <<'STUB'
#!/bin/sh
exit 0
STUB
cat >"$work/home/.local/bin/tmux-track-session" <<'STUB'
#!/bin/sh
printf '%s|%s' "$1" "$2"
STUB
chmod +x "$work/stub"/* "$work/home/.local/bin/tmux-track-session"
export REMOTE="$work/remote"

# attached_as <TMUX_PANE> [MYSSH_SESSION] — the session tmux-track-session
# would be asked to attach, as the remote shell parses the command.
attached_as() {
  : >"$REMOTE"
  (
    PATH="$work/stub:$PATH"
    rehash
    TMUX_PANE=$1
    if (( $# > 1 )); then
      MYSSH_SESSION=$2 myssh host >/dev/null 2>&1
    else
      unset MYSSH_SESSION
      myssh host >/dev/null 2>&1
    fi
  )
  HOME="$work/home" sh -c "$(cat "$REMOTE")"
}

check() {
  local desc=$1 want=$2 got=$3
  if [[ "$got" == "$want" ]]; then
    pass "$desc"
  else
    fail "$desc" "want: $want" "got : $got"
  fi
}

check "default: the session is named after the local pane" \
  "attach|local-12" "$(attached_as %12)"
check "MYSSH_SESSION names the session instead" \
  "attach|local-5" "$(attached_as %12 local-5)"
check "a session name with a space reaches the remote as one argument" \
  "attach|my work" "$(attached_as %12 'my work')"
check "an empty MYSSH_SESSION falls back to the pane" \
  "attach|local-12" "$(attached_as %12 '')"

# The command's second branch runs when the remote has no tmux-track-session:
# plain `tmux new-session -A -s <name>`, which needs the same quoting.
mkdir -p "$work/bare-home" "$work/remote-bin"
cat >"$work/remote-bin/tmux" <<'STUB'
#!/bin/sh
printf '%s|%s' "$1" "$4"
STUB
chmod +x "$work/remote-bin/tmux"
: >"$REMOTE"
(
  PATH="$work/stub:$PATH"
  rehash
  TMUX_PANE=%12
  MYSSH_SESSION='my work' myssh host >/dev/null 2>&1
)
check "without tmux-track-session, the fallback gets the same name as one argument" \
  "new-session|my work" \
  "$(HOME="$work/bare-home" PATH="$work/remote-bin:$PATH" sh -c "$(cat "$REMOTE")" 2>/dev/null)"

if (( failures == 0 )); then
  echo PASS
else
  echo "$failures failure(s)"
  exit 1
fi
