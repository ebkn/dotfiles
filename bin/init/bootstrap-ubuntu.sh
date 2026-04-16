#!/bin/bash
set -eo pipefail
# Bootstrap script for a fresh Ubuntu machine.
# Usage: curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-ubuntu.sh | bash

# When invoked via `curl ... | bash`, stdin is the pipe.  sudo and other
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

exec bash "${DOTFILES_DIR}/bin/init/ubuntu.sh" </dev/tty
