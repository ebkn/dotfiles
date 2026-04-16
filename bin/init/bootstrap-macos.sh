#!/bin/zsh
set -eo pipefail
# Bootstrap script for a fresh Mac.
# Usage: curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-macos.sh | zsh

# When invoked via `curl ... | zsh`, stdin is the pipe.  sudo and other
# interactive prompts need the real terminal, so we verify /dev/tty early
# and cache sudo credentials before any commands that require them.
if [ ! -e /dev/tty ]; then
  printf "error: /dev/tty is not available; cannot run interactively\n" >&2
  exit 1
fi

# Cache sudo credentials up front via /dev/tty (stdin is the curl pipe).
# A background loop keeps them fresh so long-running steps don't re-prompt.
sudo -S -v < /dev/tty
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

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

exec zsh "${DOTFILES_DIR}/bin/init/macos.sh" </dev/tty
