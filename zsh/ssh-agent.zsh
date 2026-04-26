# SSH agent via keychain — WSL only.
# macOS uses the system Keychain agent, so this is skipped there.
# Plain Ubuntu servers may manage SSH differently, so limit to WSL.
if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v keychain &>/dev/null; then
  eval "$(keychain --eval --quiet --agents ssh ~/.ssh/github_ed25519)"
fi
