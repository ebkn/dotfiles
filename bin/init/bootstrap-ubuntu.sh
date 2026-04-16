#!/bin/bash
set -eo pipefail
# Bootstrap script for a fresh Ubuntu machine.
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-ubuntu.sh)

if [ ! -t 0 ] && [ "${CI:-}" != "true" ]; then
  printf "error: stdin must be a terminal. Run with:\n" >&2
  printf "  bash <(curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-ubuntu.sh)\n" >&2
  exit 1
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
