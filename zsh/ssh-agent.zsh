# SSH agent selection — WSL only.
# macOS uses the system Keychain agent, so this is skipped there.
# Plain Ubuntu servers may manage SSH differently, so limit to WSL.
#
# WSL_DISTRO_NAME alone is not a reliable WSL test: only wsl.exe sets it, so it
# is absent in systemd login sessions and in any tmux server spawned from one.
# Every pane inherits the server's environment, so the whole block silently
# stopped running and every git operation fell back to prompting for the key
# passphrase. Fall back to /proc/version — the same test as common.sh:is_wsl.
if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
  if [[ -x "$HOME/.local/bin/ssh-agent-relay" ]]; then
    # Preferred: the Windows OpenSSH agent, reached through the socat relay.
    # It keeps keys DPAPI-encrypted under HKCU across reboots, so the passphrase
    # is entered once and never again — unlike keychain, whose agent dies with
    # the WSL instance. See bin/wsl/ssh-agent-relay for the full rationale.
    #
    # Only nudge systemd when the socket is missing: this runs for every new
    # shell, and `systemctl --user start` on an already-active unit still costs
    # a process spawn.
    if [[ ! -S "$HOME/.ssh/agent.sock" ]]; then
      systemctl --user start ssh-agent-relay.service 2>/dev/null
    fi
    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
  elif command -v keychain &>/dev/null; then
    # Fallback for WSL hosts without the relay installed: keychain shares one
    # agent across shells, but still costs one passphrase prompt per WSL boot.
    eval "$(keychain --eval --quiet --agents ssh ~/.ssh/github_ed25519)"
  fi
fi
