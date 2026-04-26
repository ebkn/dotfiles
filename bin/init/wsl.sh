#!/bin/bash
#
# Setup script for WSL2 (Windows Subsystem for Linux).
# On a fresh WSL instance, use the bootstrap script instead:
#   bash <(curl -fsSL -H 'Accept: application/vnd.github.raw' https://api.github.com/repos/ebkn/dotfiles/contents/bin/init/bootstrap-wsl.sh)
#
set -eo pipefail

DOTFILES_DIR="${HOME}/dotfiles"
BACKUP_DIR="${HOME}/backup"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

install_or_upgrade_apt_packages() {
  sudo apt install -y "$@"
}
. "${SCRIPT_DIR}/common.sh"

# Verify WSL environment (skip check on CI where we test on plain Ubuntu).
if [ "${CI:-}" != "true" ] && ! is_wsl; then
  printf "error: this script is intended for WSL environments\n" >&2
  printf "hint: use ubuntu.sh for plain Ubuntu, macos.sh for macOS\n" >&2
  exit 1
fi

install_or_upgrade_fzf_shell_integration() {
  local fzf_install

  # fzf's install script generates shell integration files in $HOME.
  if [ -e "${HOME}/.fzf.zsh" ] || [ -e "${HOME}/.fzf.bash" ]; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    fzf_install="$(brew --prefix fzf 2>/dev/null)/install"
    if [ -x "$fzf_install" ]; then
      "$fzf_install" --key-bindings --completion --no-update-rc
      return 0
    fi
  fi

  if [ -x "${HOME}/.fzf/install" ]; then
    "${HOME}/.fzf/install" --key-bindings --completion --no-update-rc
    return 0
  fi

  printf "warning: fzf install script not found at %s\n" "${HOME}/.fzf/install" >&2
  return 1
}

install_or_upgrade_login_shell() {
  local target_shell
  target_shell="$(brew --prefix)/bin/zsh"

  if [ "${SHELL:-}" = "$target_shell" ]; then
    return 0
  fi

  if ! grep -qxF "$target_shell" /etc/shells; then
    sudo sh -c "echo '$target_shell' >> /etc/shells"
  fi

  sudo chsh -s "$target_shell" "$USER"
}

# Copy a file or directory to a path relative to the Windows user home.
# Falls back to a warning when the Windows filesystem is unreachable (e.g. CI).
copy_to_windows() {
  local src win_relpath win_home dest
  src="$1"
  win_relpath="$2"

  if ! win_home="$(wsl_windows_home)"; then
    printf "warning: skipping Windows-side copy for %s\n" "$src" >&2
    return 0
  fi

  dest="${win_home}/${win_relpath}"
  mkdir -p "$(dirname "$dest")"

  if [ -d "$src" ]; then
    cp -r "$src" "$dest"
  else
    cp "$src" "$dest"
  fi
  printf "copied: %s -> %s\n" "$src" "$dest"
}

mkdir -p "$BACKUP_DIR"

log_step "Installing base packages"
sudo apt update
# libnotify-bin: provides `notify-send`, required by the zsh-auto-notify plugin
# (zsh/plugin.zsh) which otherwise warns "notify-send must be installed".
install_or_upgrade_apt_packages \
  build-essential \
  procps \
  git \
  curl \
  file \
  gnupg \
  ca-certificates \
  apt-transport-https \
  software-properties-common \
  keychain \
  libnotify-bin

log_step "Ensuring en_US.UTF-8 locale"
ensure_locale "en_US.UTF-8"

log_step "Cloning or updating dotfiles"
install_or_upgrade_git_repo "https://github.com/ebkn/dotfiles" "$DOTFILES_DIR"

log_step "Installing Homebrew"
install_or_upgrade_homebrew_linux
brew upgrade
brew doctor || true

log_step "Installing Google Cloud CLI"
# update-all expects gcloud to exist before shell lazy-loading is used.
install_or_upgrade_gcloud

log_step "Configuring SSH"
mkdir -p "${HOME}/.ssh/sockets"
chmod 700 "${HOME}/.ssh" "${HOME}/.ssh/sockets"
link_with_backup "${DOTFILES_DIR}/.sshconfig_base" "${HOME}/.ssh/config_base"
# Ensure shared SSH defaults are loaded via Include.
if ! grep -qF 'Include config_base' "${HOME}/.ssh/config" 2>/dev/null; then
  { echo 'Include config_base'; echo; cat "${HOME}/.ssh/config" 2>/dev/null || true; } > "${HOME}/.ssh/config.tmp"
  mv "${HOME}/.ssh/config.tmp" "${HOME}/.ssh/config"
  chmod 600 "${HOME}/.ssh/config"
fi

log_step "Linking dotfiles"
link_with_backup "${DOTFILES_DIR}/.zshrc" "${HOME}/.zshrc"
link_with_backup "${DOTFILES_DIR}/.zshenv" "${HOME}/.zshenv"
link_with_backup "${DOTFILES_DIR}/.bash_profile" "${HOME}/.bash_profile"
link_with_backup "${DOTFILES_DIR}/.bashrc" "${HOME}/.bashrc"
link_with_backup "${DOTFILES_DIR}/.tmux.conf" "${HOME}/.tmux.conf"

log_step "Installing shell packages from Homebrew"
# Brewfile-shell uses OS.mac? guards for mac-only formulae.
install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-shell"
install_or_upgrade_fzf_shell_integration

log_step "Setup shell"
if [ "$CI" != "true" ]; then
  install_or_upgrade_login_shell
fi

log_step "Installing language tools from Homebrew"
# Brewfile-lang uses OS.mac? guards for mac-only formulae.
install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-lang"

log_step "Installing other CLI tools from Homebrew"
install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-others"

# Docker: WSL2 uses Docker Desktop for Windows with WSL integration.
# Installing Docker CE here would conflict with Docker Desktop.
# See: https://docs.docker.com/desktop/wsl/
log_step "Skipping Docker CE (use Docker Desktop for Windows with WSL integration)"

# Tailscale: use the Windows-side Tailscale app for network access.
# WSL2 shares the Windows network stack when using mirrored networking mode.
log_step "Skipping Tailscale (use Windows-side Tailscale app)"

link_with_backup "${DOTFILES_DIR}/.vimrc" "${HOME}/.vimrc"
link_with_backup "${DOTFILES_DIR}/.xvimrc" "${HOME}/.xvimrc"
link_with_backup "${DOTFILES_DIR}/.ideavimrc" "${HOME}/.ideavimrc"
link_with_backup "${DOTFILES_DIR}/.textlintrc" "${HOME}/.textlintrc"
link_with_backup "${DOTFILES_DIR}/.markdownlintrc" "${HOME}/.markdownlintrc"
link_with_backup "${DOTFILES_DIR}/.clang-format" "${HOME}/.clang-format"
link_with_backup "${DOTFILES_DIR}/vim/nvim" "${HOME}/.config/nvim"
link_with_backup "${DOTFILES_DIR}/vim/coc/package.json" "${HOME}/.config/coc/extensions/package.json"
link_with_backup "${DOTFILES_DIR}/wezterm.lua" "${HOME}/.config/wezterm/wezterm.lua"
link_with_backup "${DOTFILES_DIR}/cursor/keybindings.json" "${HOME}/.config/Cursor/User/keybindings.json"
link_with_backup "${DOTFILES_DIR}/cursor/settings.json" "${HOME}/.config/Cursor/User/settings.json"

link_with_backup "${DOTFILES_DIR}/.tigrc" "${HOME}/.tigrc"
link_with_backup "${DOTFILES_DIR}/.gitignore_global" "${HOME}/.gitignore_global"
link_with_backup "${DOTFILES_DIR}/.gitconfig" "${HOME}/.gitconfig"
link_with_backup "${DOTFILES_DIR}/.gitconfig-ebkn" "${HOME}/.gitconfig-ebkn"
# On CI, disable .gitconfig's HTTPS→SSH URL rewriting — no SSH keys available.
if [ "${CI:-}" = "true" ]; then
  git config --global --unset-all 'url.git@github.com:.insteadOf' || true
fi
link_with_backup "${DOTFILES_DIR}/root/CLAUDE.md" "${HOME}/CLAUDE.md"
# Expose alternate instruction filenames used by local agent tools.
link_with_backup "${HOME}/CLAUDE.md" "${HOME}/AGENTS.md"
link_with_backup "${DOTFILES_DIR}/root/.github/copilot-instructions.md" "${HOME}/.github/copilot-instructions.md"
link_with_backup "${DOTFILES_DIR}/root/.claude/settings.json" "${HOME}/.claude/settings.json"
link_with_backup "${DOTFILES_DIR}/root/.claude/skills" "${HOME}/.claude/skills"
link_with_backup "${DOTFILES_DIR}/root/.claude/hooks" "${HOME}/.claude/hooks"
link_with_backup "${DOTFILES_DIR}/root/.codex/rules/default.rules" "${HOME}/.codex/rules/default.rules"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/commit" "${HOME}/.codex/skills/commit"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/create-pr" "${HOME}/.codex/skills/create-pr"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/update-pr" "${HOME}/.codex/skills/update-pr"
install_or_upgrade_claude

log_step "Installing Node.js toolchain"
install_or_upgrade_volta
install_or_upgrade_node_with_volta
# Keep this list aligned with zsh/alias.zsh:update-all npm global installs.
install_or_upgrade_npm_global "diagnostic-languageserver"
install_or_upgrade_npm_global "markdownlint-cli"
install_or_upgrade_npm_global "textlint"
install_or_upgrade_npm_global "git-delete-squashed"
install_or_upgrade_npm_global "yarn"
install_or_upgrade_npm_global "@openai/codex"
install_or_upgrade_npm_global "@githubnext/github-copilot-cli"
link_with_backup "${DOTFILES_DIR}/.eslintrc.js" "${HOME}/.eslintrc.js"
link_with_backup "${DOTFILES_DIR}/tsconfig.json" "${HOME}/tsconfig.json"

# others
link_with_backup "${DOTFILES_DIR}/.rgignore" "${HOME}/.rgignore"
link_with_backup "${DOTFILES_DIR}/.sqliterc" "${HOME}/.sqliterc"

# scripts
link_with_backup "${DOTFILES_DIR}/tmux-restore-tabs" "${HOME}/.local/bin/tmux-restore-tabs"
link_with_backup "${DOTFILES_DIR}/tmux-pane-titles" "${HOME}/.local/bin/tmux-pane-titles"
link_with_backup "${DOTFILES_DIR}/tmux-track-session" "${HOME}/.local/bin/tmux-track-session"
link_with_backup "${DOTFILES_DIR}/bin/fzf-files" "${HOME}/.local/bin/fzf-files"

log_step "Ensuring tmux plugin manager"
install_or_upgrade_git_repo "https://github.com/tmux-plugins/tpm" "${HOME}/.tmux/plugins/tpm"
"${HOME}/.tmux/plugins/tpm/bin/install_plugins"

# Copy GUI app configs to the Windows side so WezTerm and Cursor running
# natively on Windows pick them up.  Re-run the init script to resync
# after editing these dotfiles.
if is_wsl; then
  log_step "Copying configs to Windows side"
  copy_to_windows "${DOTFILES_DIR}/wezterm.lua" ".config/wezterm/wezterm.lua"
  copy_to_windows "${DOTFILES_DIR}/cursor/keybindings.json" "AppData/Roaming/Cursor/User/keybindings.json"
  copy_to_windows "${DOTFILES_DIR}/cursor/settings.json" "AppData/Roaming/Cursor/User/settings.json"
fi

log_step "Setup complete"
