#!/bin/zsh
#
# Bootstrap script for a fresh Mac.
# Usage: curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-macos.sh | zsh
#
set -eo pipefail

# When invoked via `curl ... | zsh`, stdin is the pipe.  We must NOT
# `exec </dev/tty` here — zsh reads the remaining script from stdin, so
# replacing it would cause the shell to hang waiting on the TTY.
# Individual commands either use non-interactive flags (--agree-to-license,
# -y, NONINTERACTIVE=1) or read passwords from /dev/tty internally (sudo).
# The final exec redirects stdin to /dev/tty for the setup script.

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

# The setup script may contain interactive prompts (e.g. Homebrew
# installer).  Reconnect stdin to the TTY so they can read input.
if [ ! -e /dev/tty ]; then
  printf "error: /dev/tty is not available; cannot run the setup script interactively\n" >&2
  exit 1
fi
exec zsh "${DOTFILES_DIR}/bin/init/macos.sh" </dev/tty
