#!/bin/bash
#
# Bootstrap script for a fresh Ubuntu machine.
# Usage: curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-ubuntu.sh | bash
#
set -eo pipefail

# When invoked via `curl ... | bash`, stdin is the pipe.  We must NOT
# `exec </dev/tty` here — bash reads the remaining script from stdin, so
# replacing it would cause the shell to hang waiting on the TTY.
# Instead, attach /dev/tty only to specific commands that need interactive
# input (e.g. sudo), and pass it to the final exec.

DOTFILES_DIR="${HOME}/dotfiles"

# Install git if missing.
if ! command -v git >/dev/null 2>&1; then
  printf "Installing git...\n"
  sudo apt update </dev/tty
  sudo apt install -y git </dev/tty
fi

# Clone dotfiles if missing.
if [ ! -d "$DOTFILES_DIR" ]; then
  printf "Cloning dotfiles...\n"
  git clone https://github.com/ebkn/dotfiles "$DOTFILES_DIR"
fi

# Reconnect stdin to the TTY for the setup script so sudo and other
# interactive prompts work correctly.
if [ -e /dev/tty ]; then
  exec bash "${DOTFILES_DIR}/bin/init/ubuntu.sh" </dev/tty
else
  exec bash "${DOTFILES_DIR}/bin/init/ubuntu.sh"
fi
