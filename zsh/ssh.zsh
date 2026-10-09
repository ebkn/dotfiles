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
# @ssh_host is read by .tmux.conf (status-left, the purple pane border, and the
# host-naming menu that guards d / q / F12) and by bin/tmux-agents (which local
# pane holds a given host). @ssh_my_machine is set only for `myssh`, and means
# "tmux and these dotfiles are on the far end", which is what makes .tmux.conf
# pass prefix + p/t/o/u through to the nested remote tmux instead of running the
# local popup, and offer the "remote" item in that guard menu.
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
# (~3 pkt/s, ~400 B/s) while any connection to the host is open pins the radio
# in active mode and keeps Tailscale's UDP NAT mapping warm for away-from-home
# direct paths.
#
# The ping must be disowned (&!): as an ordinary job it would announce itself
# ("[1] 12345") on every connection and report "terminated" on every
# disconnect. But disowning also puts it out of reach of the SIGHUP a shell
# sends its jobs on the way out, and myssh's own kill is only reached when
# myssh *returns* — so closing the pane mid-session, or killing the shell, left
# a ping running at three packets a second with nothing left to stop it.
#
# The supervisor is what bounds it. It is the disowned process; the ping is its
# child; it wakes every few seconds to check that a shell which asked for the
# keepalive is still alive, and kills the ping when none is. So a leak costs at
# most one poll interval instead of lasting until reboot.
#
# ONE ping per host, not per connection. The radio and the NAT mapping are per
# host, so a second ping keeps nothing warmer -- and with a myssh per tab, four
# tabs on one host were running four (~27 packets a second, measured as more
# traffic than all four terminals together). Connections live in separate
# shells, so the sharing goes through the filesystem, under $_SSH_KEEPALIVE_DIR:
#
#   <host>.owners/<pid>  one file per shell with a connection open to <host>
#   <host>.lock          symlink to the pid of the supervisor that pings it
#
# Every start registers its owner file FIRST and then launches a candidate
# supervisor, which pings only if it can take the lock. A supervisor that finds
# no live owner drops the lock and then looks once more: a shell that
# registered in between saw the lock still held and left the ping to it, so
# either that supervisor re-takes the lock or the newcomer's own candidate
# does. That ordering is what rules out a session with no ping; the lock rules
# out two pings. Two gaps are accepted: two newcomers both clearing the same
# stale lock can each end up pinging, until their owners leave; and a stale
# lock whose pid has been reused reads as held, leaving that host unpinged
# until the process now holding the pid exits.
#
# The interval and the directory are variables so the tests do not have to
# sleep for real seconds or share state with a live session; nothing else
# should set them.
: ${_SSH_KEEPALIVE_POLL:=5}
: ${_SSH_KEEPALIVE_DIR:=${TMPDIR:-/tmp}/myssh-keepalive-$UID}
typeset -g _SSH_KEEPALIVE_OWNER=""

# _ssh_keepalive_lock_take <lock> <pid> -- succeed when <pid> now holds <lock>.
# `ln -s` is the atomic step, and the link's target carries the holder's pid,
# so there is never a lock whose owner cannot be read. A holder that is no
# longer running (SIGKILL runs no trap) is stale, and is replaced.
_ssh_keepalive_lock_take() {
  local lock=$1 me=$2 holder
  ln -s "$me" "$lock" 2>/dev/null && return 0
  holder=$(readlink "$lock" 2>/dev/null)
  if [ -n "$holder" ]; then
    kill -0 "$holder" 2>/dev/null && return 1
    command rm -f "$lock"
  fi
  # An empty holder means the lock vanished between the two calls: retry
  # without the rm, which could otherwise remove a lock someone just took.
  ln -s "$me" "$lock" 2>/dev/null
}

# _ssh_keepalive_lock_drop <lock> <pid> -- release <lock> if <pid> holds it.
_ssh_keepalive_lock_drop() {
  [ "$(readlink "$1" 2>/dev/null)" = "$2" ] && command rm -f "$1"
  return 0
}

# _ssh_keepalive_owners_live <dir> -- succeed when a registered shell is alive.
# Prunes the dead ones as it goes, so a shell that died without myssh
# returning stops counting at the next poll.
_ssh_keepalive_owners_live() {
  local f live=1
  for f in "$1"/*(N); do
    if kill -0 "${f:t}" 2>/dev/null; then
      live=0
    else
      command rm -f "$f"
    fi
  done
  return $live
}

# _ssh_keepalive_start <target> [owner-pid]
# Registers this shell as needing a ping to <target> and makes sure one runs.
# Sets _SSH_KEEPALIVE_OWNER, or leaves it empty when there is nothing to ping.
_ssh_keepalive_start() {
  local target=$1 owner=${2:-$$}
  _SSH_KEEPALIVE_OWNER=""
  [ -n "$target" ] || return 0
  (( $+commands[ping] )) || return 0

  local key=${target//\//_}
  local lock="$_SSH_KEEPALIVE_DIR/$key.lock"
  local owners="$_SSH_KEEPALIVE_DIR/$key.owners"
  mkdir -m 700 -p "$_SSH_KEEPALIVE_DIR" 2>/dev/null || return 0
  mkdir -p "$owners" 2>/dev/null || return 0
  : >"$owners/$owner" || return 0
  _SSH_KEEPALIVE_OWNER="$owners/$owner"

  {
    # $$ in a subshell is still the parent shell's pid; the lock needs this one.
    zmodload -F zsh/system p:sysparams
    local me=${sysparams[pid]}
    _ssh_keepalive_lock_take "$lock" "$me" || exit 0

    ping -i 0.3 -q "$target" >/dev/null 2>&1 &
    local ping_pid=$!
    # The trap covers being killed outright; the loop covers every owner
    # leaving, whether myssh returned or its shell died. `sleep` is
    # interruptible, so the trap runs promptly.
    trap 'kill $ping_pid 2>/dev/null; _ssh_keepalive_lock_drop "$lock" "$me"; exit' TERM INT HUP
    while kill -0 $ping_pid 2>/dev/null; do
      if ! _ssh_keepalive_owners_live "$owners"; then
        _ssh_keepalive_lock_drop "$lock" "$me"
        # The second look described above the variables.
        _ssh_keepalive_owners_live "$owners" &&
          _ssh_keepalive_lock_take "$lock" "$me" && continue
        break
      fi
      # Keep the state young: macOS's dirhelper deletes $TMPDIR files older
      # than 3 days, and a connection can outlive that. A swept owner file
      # reads as "nobody left" and stops the ping; a swept lock lets the next
      # connection start a second one. The dead were pruned just above.
      touch "$owners"/*(N) 2>/dev/null
      touch -h "$lock" 2>/dev/null
      sleep "$_SSH_KEEPALIVE_POLL"
    done
    kill $ping_pid 2>/dev/null
    _ssh_keepalive_lock_drop "$lock" "$me"
  } >/dev/null 2>&1 &!
}

# Unregisters this shell. The supervisor notices at its next poll, and stops
# the ping only if no other connection to that host remains.
_ssh_keepalive_stop() {
  [ -n "$_SSH_KEEPALIVE_OWNER" ] || return 0
  command rm -f "$_SSH_KEEPALIVE_OWNER"
  _SSH_KEEPALIVE_OWNER=""
}

# myssh: ssh into "my machines" — hosts where tmux + tmux-track-session
# are deployed. Adds auto-reconnect via autossh and attaches to a per-pane
# remote tmux session. Sets `@ssh_my_machine` on the local pane so tmux
# bindings (prefix + p/t/o/u) pass the prefix chord through to the nested
# remote tmux instead of falling back to running the local popup / copy-mode.
# Shares one low-rate keepalive ping per host, for as long as any connection
# to it is open, to hold this Wi-Fi-first client's radio out of 802.11
# power-save doze
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

  # Scratch file for the reconnect notice; see the autossh call below.
  local notice_state=""

  # @ssh_my_machine only when autossh is actually taking over: the option
  # promises a nested remote tmux for prefix + p/t/o/u to reach, and the
  # fallback path below is a plain one-shot ssh with nothing to reach.
  local my_machine=""
  $use_autossh && my_machine=1
  $decorate && _ssh_decorate_on "$host" "$my_machine"

  if $use_autossh; then
    # Interactive: auto-reconnect with per-pane remote tmux session.
    # Each local tmux pane gets its own remote session so multiple panes
    # connecting to the same host stay independent. On reconnect, the remote
    # command goes through tmux-track-session attach (the last session this
    # connection visited, if no other client holds it); `new-session -A` is
    # only the fallback when that script is not deployed.
    # NOTE: `exit` on the remote destroys the session (last window gone).
    # Closing the local pane or losing the network leaves the remote
    # session detached (shell still running), which autossh reattaches
    # on reconnect. To auto-clean orphaned sessions, set
    # `set -g destroy-unattached on` in the remote tmux.conf.
    local remote_session="main"
    if [ -n "$TMUX_PANE" ]; then
      remote_session="local-${TMUX_PANE#%}"
    fi
    # bin/tmux-restore-ssh-tabs names an existing session instead: a restored
    # tab is a new pane, and its own pane id would open a fresh empty session.
    [ -n "${MYSSH_SESSION:-}" ] && remote_session=$MYSSH_SESSION
    # Quoted for the remote shell, which parses the command below once more.
    local remote_session_q=${(q)remote_session}
    # Ping the ssh-config-resolved hostname, so the keepalive exercises the
    # same endpoint the tunnel itself uses. See _ssh_keepalive_start.
    _ssh_keepalive_start \
      "$(command ssh -G "$host" 2>/dev/null | awk '/^hostname /{print $2; exit}')"
    # AUTOSSH_PATH points autossh at bin/autossh-ssh, which draws the centred
    # "reconnecting" notice once per attempt and keeps ssh's per-attempt
    # diagnostics off the stale remote frame. It is a shim, not a replacement
    # for autossh: the restart policy stays autossh's. The state file is its
    # only memory between attempts (autossh execs it afresh each time) and is
    # per-connection, so it is created here and removed below; without it the
    # shim is a transparent `exec ssh`, which is also what happens when the
    # shim is not deployed on this machine.
    #
    # `local -x` rather than a command prefix: `${var:+FOO=bar} autossh` does
    # not work, because a command's assignment prefixes are recognised when the
    # line is parsed, so an assignment produced by an expansion arrives as an
    # ordinary argument. Exporting for the function's scope is the same
    # lifetime as the connection.
    local notice_shim="$HOME/.local/bin/autossh-ssh"
    if $decorate && [ -x "$notice_shim" ]; then
      notice_state=$(mktemp -t myssh-notice 2>/dev/null)
      if [ -n "$notice_state" ]; then
        local -x AUTOSSH_PATH="$notice_shim"
        local -x AUTOSSH_NOTICE_STATE="$notice_state"
        local -x AUTOSSH_NOTICE_HOST="$host"
      fi
    fi
    # ControlPath=none: bypass stale ControlMaster sockets that can block reconnection.
    # autossh manages its own reconnection; shared sockets from ControlPersist interfere.
    # tmux-track-session: reattach to the last-used session if the user switched
    # sessions on the remote. Falls back to plain tmux if script is not deployed.
    AUTOSSH_GATETIME=0 autossh -M 0 \
      -o ControlPath=none "${ssh_opts[@]}" -t "$host" \
      "~/.local/bin/tmux-track-session attach ${remote_session_q} 2>/dev/null || tmux new-session -A -s ${remote_session_q} 2>/dev/null || exec \$SHELL -l"
  else
    command ssh "$@"
  fi
  local ret=$?

  # After $?, never before: the notice state is per-connection scratch, and
  # cleaning it up ahead of the read would report rm's status as the
  # connection's. ".log" is the file bin/autossh-ssh writes beside the state
  # file; a scratch file it adds has to be named here too, or it leaks.
  [ -n "$notice_state" ] && rm -f "$notice_state" "$notice_state.log"

  _ssh_keepalive_stop

  $decorate && _ssh_decorate_off

  return $ret
}
