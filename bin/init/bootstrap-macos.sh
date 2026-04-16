#!/bin/zsh
set -eo pipefail
# Bootstrap script for a fresh Mac.
# Usage: zsh <(curl -fsSL -H 'Accept: application/vnd.github.raw' https://api.github.com/repos/ebkn/dotfiles/contents/bin/init/bootstrap-macos.sh)

if [ ! -t 0 ] && [ "${CI:-}" != "true" ]; then
  printf "error: stdin must be a terminal. Run with:\n" >&2
  printf "  zsh <(curl -fsSL -H 'Accept: application/vnd.github.raw' https://api.github.com/repos/ebkn/dotfiles/contents/bin/init/bootstrap-macos.sh)\n" >&2
  exit 1
fi

DOTFILES_DIR="${HOME}/dotfiles"

# Install Xcode Command Line Tools if missing.
if ! xcode-select -p >/dev/null 2>&1; then
  printf "Installing Xcode Command Line Tools...\n"
  xcode-select --install
  # Wait until the installer finishes.
  until xcode-select -p >/dev/null 2>&1; do
    sleep 5
  done
fi

# Install Rosetta 2 on Apple Silicon if missing.
if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/pgrep -q oahd; then
  printf "Installing Rosetta 2...\n"
  sudo softwareupdate --install-rosetta --agree-to-license
fi

# Clone dotfiles if missing.
if [ ! -d "$DOTFILES_DIR" ]; then
  printf "Cloning dotfiles...\n"
  git clone https://github.com/ebkn/dotfiles "$DOTFILES_DIR"
fi

exec zsh "${DOTFILES_DIR}/bin/init/macos.sh"
