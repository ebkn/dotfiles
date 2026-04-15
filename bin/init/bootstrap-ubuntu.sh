#!/bin/bash
#
# Bootstrap script for a fresh Ubuntu machine.
# Usage: curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-ubuntu.sh | bash
#
set -eo pipefail

# When invoked via `curl ... | bash`, stdin is the pipe.  Reconnect to
# the TTY early so every command (sudo, installers) can prompt.
if [ ! -t 0 ] && [ -e /dev/tty ]; then
  exec </dev/tty
fi

DOTFILES_DIR="${HOME}/dotfiles"

# Install git if missing.
if ! command -v git >/dev/null 2>&1; then
  printf "Installing git...\n"
  sudo apt update
  sudo apt install -y git
fi

# Clone dotfiles if missing.
if [ ! -d "$DOTFILES_DIR" ]; then
  printf "Cloning dotfiles...\n"
  git clone https://github.com/ebkn/dotfiles "$DOTFILES_DIR"
fi

exec bash "${DOTFILES_DIR}/bin/init/ubuntu.sh"
