#!/bin/bash
set -eo pipefail
# Bootstrap script for a fresh WSL2 instance.
# Usage: bash <(curl -fsSL -H 'Accept: application/vnd.github.raw' https://api.github.com/repos/ebkn/dotfiles/contents/bin/init/bootstrap-wsl.sh)

if [ ! -t 0 ] && [ "${CI:-}" != "true" ]; then
  printf "error: stdin must be a terminal. Run with:\n" >&2
  printf "  bash <(curl -fsSL -H 'Accept: application/vnd.github.raw' https://api.github.com/repos/ebkn/dotfiles/contents/bin/init/bootstrap-wsl.sh)\n" >&2
  exit 1
fi

DOTFILES_DIR="${HOME}/dotfiles"

# Install git if missing.
if ! command -v git >/dev/null 2>&1; then
  printf "Installing git...\n"
  sudo apt update
  sudo apt install -y git
fi

# Clone or update dotfiles so wsl.sh always runs the latest code.
if [ ! -d "$DOTFILES_DIR" ]; then
  printf "Cloning dotfiles...\n"
  git clone https://github.com/ebkn/dotfiles "$DOTFILES_DIR"
else
  printf "Updating dotfiles...\n"
  git -C "$DOTFILES_DIR" fetch --all --prune
  git -C "$DOTFILES_DIR" merge --ff-only || printf "warning: could not fast-forward dotfiles\n" >&2
fi

exec bash "${DOTFILES_DIR}/bin/init/wsl.sh"
