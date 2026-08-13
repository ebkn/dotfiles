#!/bin/bash
set -eo pipefail
# Bootstrap script for a fresh Ubuntu machine.
# Usage: bash <(curl -fsSL -H 'Accept: application/vnd.github.raw' https://api.github.com/repos/ebkn/dotfiles/contents/bin/init/bootstrap-ubuntu.sh)

if [ ! -t 0 ] && [ "${CI:-}" != "true" ]; then
  printf "error: stdin must be a terminal. Run with:\n" >&2
  printf "  bash <(curl -fsSL -H 'Accept: application/vnd.github.raw' https://api.github.com/repos/ebkn/dotfiles/contents/bin/init/bootstrap-ubuntu.sh)\n" >&2
  exit 1
fi

DOTFILES_DIR="${HOME}/dotfiles"

# Install git if missing.
if ! command -v git >/dev/null 2>&1; then
  printf "Installing git...\n"
  sudo apt update
  sudo apt install -y git
fi

# Clone or update dotfiles so ubuntu.sh always runs the latest code.
#
# DOTFILES_SKIP_UPDATE=1 leaves an existing checkout untouched, for callers that
# decide the revision themselves: CI validating a pushed branch, or a local
# re-run from a work-in-progress clone. Without it the fetch/merge silently
# swaps in the default branch, so the run validates code nobody asked for.
if [ ! -d "$DOTFILES_DIR" ]; then
  if [ "${DOTFILES_SKIP_UPDATE:-}" = "1" ]; then
    printf "error: DOTFILES_SKIP_UPDATE=1 but %s does not exist\n" "$DOTFILES_DIR" >&2
    exit 1
  fi
  printf "Cloning dotfiles...\n"
  git clone https://github.com/ebkn/dotfiles "$DOTFILES_DIR"
elif [ "${DOTFILES_SKIP_UPDATE:-}" = "1" ]; then
  printf "Using existing checkout at %s (DOTFILES_SKIP_UPDATE=1)\n" "$DOTFILES_DIR"
else
  printf "Updating dotfiles...\n"
  git -C "$DOTFILES_DIR" fetch --all --prune
  git -C "$DOTFILES_DIR" merge --ff-only || printf "warning: could not fast-forward dotfiles\n" >&2
fi

exec bash "${DOTFILES_DIR}/bin/init/ubuntu.sh"
