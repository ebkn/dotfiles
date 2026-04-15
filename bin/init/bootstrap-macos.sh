#!/bin/zsh
#
# Bootstrap script for a fresh Mac.
# Usage: curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-macos.sh | zsh
#
set -eo pipefail

# When invoked via `curl ... | zsh`, stdin is the pipe.  We must NOT
# `exec </dev/tty` here — zsh reads the remaining script from stdin, so
# replacing it would cause the shell to hang waiting on the TTY.
# Instead, attach /dev/tty only to specific commands that need interactive
# input (e.g. sudo), and pass it to the final exec.

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
  sudo softwareupdate --install-rosetta --agree-to-license </dev/tty
fi

# Clone dotfiles if missing.
if [ ! -d "$DOTFILES_DIR" ]; then
  printf "Cloning dotfiles...\n"
  git clone https://github.com/ebkn/dotfiles "$DOTFILES_DIR"
fi

# Reconnect stdin to the TTY for the setup script so sudo and other
# interactive prompts work correctly.
if [ -e /dev/tty ]; then
  exec zsh "${DOTFILES_DIR}/bin/init/macos.sh" </dev/tty
else
  exec zsh "${DOTFILES_DIR}/bin/init/macos.sh"
fi
