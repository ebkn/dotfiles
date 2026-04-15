#!/bin/bash
#
# Bootstrap script for a fresh Ubuntu machine.
# Usage: curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-ubuntu.sh | bash
#
set -eo pipefail

# When invoked via `curl ... | bash`, stdin is the pipe.  We must NOT
# `exec </dev/tty` here — bash reads the remaining script from stdin, so
# replacing it would cause the shell to hang waiting on the TTY.
# Individual commands either use non-interactive flags (-y, NONINTERACTIVE=1)
# or read passwords from /dev/tty internally (sudo).
# The final exec redirects stdin to /dev/tty for the setup script.

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

# The setup script may contain interactive prompts (e.g. Homebrew
# installer).  Reconnect stdin to the TTY so they can read input.
if [ ! -e /dev/tty ]; then
  printf "error: /dev/tty is not available; cannot run the setup script interactively\n" >&2
  exit 1
fi
exec bash "${DOTFILES_DIR}/bin/init/ubuntu.sh" </dev/tty
