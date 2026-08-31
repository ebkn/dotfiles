# ssh: the argv parser both wrappers share, the plain `ssh` wrapper that only
# decorates the tmux pane, and `myssh` for machines that run these dotfiles.
#
# The pane options set here -- @ssh_host and @ssh_my_machine -- are the contract
# with tmux: .tmux.conf colours the pane and passes prefix chords through to the
# nested remote tmux from them, and bin/tmux-agents uses @ssh_my_machine to
# decide which hosts to query. The comment above the popup bindings in
# .tmux.conf documents what each one means.
#
# Not to be confused with zsh/ssh-agent.zsh, which picks the SSH agent on WSL.
# Pinned by zsh/ssh-parse-argv.test.zsh.

# Shared argv parser for the ssh/myssh wrappers below.
# Walks the argument list the same way ssh itself does and populates:
#   _SSH_PARSE_HOST           — the target host argument (empty if not found)
#   _SSH_PARSE_OPTS           — ssh options preceding the host, in order
#   _SSH_PARSE_HAS_REMOTE_CMD — true when a command follows the host (e.g. `ssh h ls`)
_ssh_parse_argv() {
  _SSH_PARSE_OPTS=()
  _SSH_PARSE_HOST=""
  _SSH_PARSE_HAS_REMOTE_CMD=false
  local skip_next=false
  local found_host=false
  local arg
  for arg in "$@"; do
    if $skip_next; then
      skip_next=false
      _SSH_PARSE_OPTS+=("$arg")
      continue
    fi
    case "$arg" in
      # Every ssh(1) option that takes a SEPARATE argument, so the argument is
      # not mistaken for the host. Kept in the manual's own order (upper before
      # lower per letter) to make it diffable against `man ssh` when openssh
      # adds one — the only way this list rots. Pinned by
      # zsh/ssh-parse-argv.test.zsh.
      -[BbcDEeFIiJLlmOoPpQRSWw])
        skip_next=true
        _SSH_PARSE_OPTS+=("$arg")
        ;;
      -*)
        _SSH_PARSE_OPTS+=("$arg")
        ;;
      *)
        if $found_host; then
          _SSH_PARSE_HAS_REMOTE_CMD=true
          break
        fi
        _SSH_PARSE_HOST="$arg"
        found_host=true
        ;;
    esac
  done
}

# Pane decoration, shared by both wrappers below. Kept together because the two
# halves have to stay symmetrical: anything _on sets, _off has to put back, and
# when they were written out twice each the pairing was four places to keep in
# step rather than one.
#
# Neither is guarded on `[ -t 1 ]` — the caller decides that, since it also
# decides whether to decorate at all. See the comment on `decorate` in ssh().

# _ssh_decorate_on <host> [my_machine]
#
# @ssh_host is read by .tmux.conf (status-left, the purple pane border) and by
# bin/tmux-agents (which local pane holds a given host). @ssh_my_machine is set
# only for `myssh`, and means "tmux and these dotfiles are on the far end", which
# is what makes .tmux.conf pass prefix + p/t/o/u through to the nested remote
# tmux instead of running the local popup.
_ssh_decorate_on() {
  local host=$1 my_machine=${2:-}
  [ -n "$TMUX" ] || return 0

  # Everforest dark hard: bg_dim (#1e2326) — slightly darker than bg0
  tmux select-pane -P 'bg=#1e2326'
  tmux set-option -p @ssh_host "${host:-unknown}"
  [ -n "$my_machine" ] && tmux set-option -p @ssh_my_machine 1
  tmux-pane-titles 2>/dev/null
}

# _ssh_decorate_off
#
# The terminal reset comes first and happens even outside tmux: it undoes state
# a remote tmux may have left behind on an abrupt disconnect (SGR/X10/
# button-event/all-mouse tracking, bracketed paste, cursor visibility, text
# attributes). Without it, mouse scroll produces raw escape sequences like
# "65;61;46M" instead of scrolling.
#
# @ssh_my_machine is cleared unconditionally, including on the plain `ssh` path
# that never sets it. Unsetting an option that was never set is a silent no-op
# (verified), and clearing both is what keeps this the exact inverse of _on.
_ssh_decorate_off() {
  printf '\e[?9l\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?2004l\e[?25h\e[0m'
  [ -n "$TMUX" ] || return 0

  tmux select-pane -P default
  tmux set-option -p -u @ssh_host
  tmux set-option -p -u @ssh_my_machine
  tmux-pane-titles 2>/dev/null
}

# ssh wrapper: lightweight tmux visual indicator for any remote.
# Makes no assumption about what is installed on the remote — safe to use
# against foreign hosts, CI runners, jump boxes, etc. For interactive work
# on your own machines (where tmux + tmux-track-session are deployed and
# auto-reconnect is desired), use `myssh` instead.
# Bypass: use `command ssh` to skip this wrapper entirely.
ssh() {
  _ssh_parse_argv "$@"
  local host="$_SSH_PARSE_HOST"

  # Only decorate the terminal when stdout is one. zsh's _remote_files (remote
  # path completion for scp/sftp) shells out via _call_program, which `eval`s
  # "ssh <host> ls …" in the *current* shell — so it resolves to this wrapper,
  # not the binary. With stdout a pipe, the reset sequence below lands in the
  # captured `ls` output and shows up as a garbage completion candidate, and
  # the tmux calls repaint the pane on every TAB. Same for `ssh host cmd > f`.
  local decorate=false
  [ -t 1 ] && decorate=true

  $decorate && _ssh_decorate_on "$host"

  command ssh "$@"
  local ret=$?

  $decorate && _ssh_decorate_off

  return $ret
}

# Wi-Fi keepalive.
#
# This client stays on Wi-Fi (it roams to the office), and 802.11 power save
# lets the radio doze during typing pauses — the first keystroke after a pause
# pays the wake-up cost, measured at 70-100ms on the home LAN. A low-rate ping
# (~3 pkt/s, ~400 B/s) for the session's lifetime pins the radio in active mode
# and keeps Tailscale's UDP NAT mapping warm for away-from-home direct paths.
#
# The ping must be disowned (&!): as an ordinary job it would announce itself
# ("[1] 12345") on every connection and report "terminated" on every
# disconnect. But disowning also puts it out of reach of the SIGHUP a shell
# sends its jobs on the way out, and myssh's own kill is only reached when
# myssh *returns* — so closing the pane mid-session, or killing the shell, left
# a ping running at three packets a second with nothing left to stop it.
#
# The supervisor is what bounds it. It is the disowned process; the ping is its
# child; it wakes every few seconds to check the shell that asked for the
# keepalive is still alive, and kills the ping when it is not. So a leak now
# costs at most one poll interval instead of lasting until reboot.
#
# The interval is a variable so the tests do not have to sleep for real
# seconds; nothing else should set it.
: ${_SSH_KEEPALIVE_POLL:=5}
typeset -g _SSH_KEEPALIVE_PID=""

# _ssh_keepalive_start <target> [owner-pid]
# Sets _SSH_KEEPALIVE_PID, or leaves it empty when there is nothing to ping.
_ssh_keepalive_start() {
  local target=$1 owner=${2:-$$}
  _SSH_KEEPALIVE_PID=""
  [ -n "$target" ] || return 0
  (( $+commands[ping] )) || return 0

  {
    ping -i 0.3 -q "$target" >/dev/null 2>&1 &
    local ping_pid=$!
    # The trap covers the ordinary path (myssh kills this supervisor when the
    # connection ends); the loop covers the shell dying without myssh ever
    # returning. `sleep` is interruptible, so the trap runs promptly.
    trap 'kill $ping_pid 2>/dev/null; exit' TERM INT HUP
    while kill -0 $owner 2>/dev/null && kill -0 $ping_pid 2>/dev/null; do
      sleep "$_SSH_KEEPALIVE_POLL"
    done
    kill $ping_pid 2>/dev/null
  } >/dev/null 2>&1 &!
  _SSH_KEEPALIVE_PID=$!
}

_ssh_keepalive_stop() {
  [ -n "$_SSH_KEEPALIVE_PID" ] || return 0
  kill "$_SSH_KEEPALIVE_PID" 2>/dev/null
  _SSH_KEEPALIVE_PID=""
}

# myssh: ssh into "my machines" — hosts where tmux + tmux-track-session
# are deployed. Adds auto-reconnect via autossh and attaches to a per-pane
# remote tmux session. Sets `@ssh_my_machine` on the local pane so tmux
# bindings (prefix + p/t/o/u) pass the prefix chord through to the nested
# remote tmux instead of falling back to running the local popup / copy-mode.
# Runs a low-rate keepalive ping for the session's lifetime to hold this
# Wi-Fi-first client's radio out of 802.11 power-save doze
# (see _ssh_keepalive_start above).
#
# Falls back to plain `command ssh` without setting `@ssh_my_machine` when:
#   - a remote command is given (e.g. `myssh host 'ls'`) — one-shot
#   - autossh is not installed
#
# Bypass: use plain `ssh` (the wrapper above) or `command ssh`.
myssh() {
  _ssh_parse_argv "$@"
  local host="$_SSH_PARSE_HOST"
  local ssh_opts=("${_SSH_PARSE_OPTS[@]}")
  local has_remote_cmd="$_SSH_PARSE_HAS_REMOTE_CMD"

  local use_autossh=false
  if ! $has_remote_cmd && (( $+commands[autossh] )); then
    use_autossh=true
  fi

  # See the ssh() wrapper above: terminal decoration only makes sense when
  # stdout is a terminal, otherwise the escape sequence corrupts captured output.
  local decorate=false
  [ -t 1 ] && decorate=true

  # @ssh_my_machine only when autossh is actually taking over: the option
  # promises a nested remote tmux for prefix + p/t/o/u to reach, and the
  # fallback path below is a plain one-shot ssh with nothing to reach.
  local my_machine=""
  $use_autossh && my_machine=1
  $decorate && _ssh_decorate_on "$host" "$my_machine"

  if $use_autossh; then
    # Interactive: auto-reconnect with per-pane remote tmux session.
    # Each local tmux pane gets its own remote session so multiple panes
    # connecting to the same host stay independent. On reconnect, autossh
    # reattaches to the same session via -A (attach-or-create).
    # NOTE: `exit` on the remote destroys the session (last window gone).
    # Closing the local pane or losing the network leaves the remote
    # session detached (shell still running), which autossh reattaches
    # on reconnect. To auto-clean orphaned sessions, set
    # `set -g destroy-unattached on` in the remote tmux.conf.
    local remote_session="main"
    if [ -n "$TMUX_PANE" ]; then
      remote_session="local-${TMUX_PANE#%}"
    fi
    # Ping the ssh-config-resolved hostname, so the keepalive exercises the
    # same endpoint the tunnel itself uses. See _ssh_keepalive_start.
    _ssh_keepalive_start \
      "$(command ssh -G "$host" 2>/dev/null | awk '/^hostname /{print $2; exit}')"
    # ControlPath=none: bypass stale ControlMaster sockets that can block reconnection.
    # autossh manages its own reconnection; shared sockets from ControlPersist interfere.
    # tmux-track-session: reattach to the last-used session if the user switched
    # sessions on the remote. Falls back to plain tmux if script is not deployed.
    AUTOSSH_GATETIME=0 autossh -M 0 \
      -o ControlPath=none "${ssh_opts[@]}" -t "$host" \
      "~/.local/bin/tmux-track-session attach ${remote_session} 2>/dev/null || tmux new-session -A -s ${remote_session} 2>/dev/null || exec \$SHELL -l"
  else
    command ssh "$@"
  fi
  local ret=$?

  _ssh_keepalive_stop

  $decorate && _ssh_decorate_off

  return $ret
}
