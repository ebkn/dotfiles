#!/bin/bash
#
# Setup script for Ubuntu. Requires git.
# On a fresh machine, use the bootstrap script instead:
#   bash <(curl -fsSL https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-ubuntu.sh)
#
set -eo pipefail

DOTFILES_DIR="${HOME}/dotfiles"
BACKUP_DIR="${HOME}/backup"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

install_or_upgrade_apt_packages() {
  sudo apt install -y "$@"
}
. "${SCRIPT_DIR}/common.sh"

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

install_or_upgrade_docker_repo() {
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
}

mkdir -p "$BACKUP_DIR"

log_step "Installing base packages"
sudo apt update
install_or_upgrade_apt_packages \
  build-essential \
  procps \
  git \
  curl \
  file \
  gnupg \
  ca-certificates \
  apt-transport-https \
  software-properties-common

log_step "Cloning or updating dotfiles"
install_or_upgrade_git_repo "https://github.com/ebkn/dotfiles" "$DOTFILES_DIR"

log_step "Installing Homebrew"
install_or_upgrade_homebrew_linux
brew upgrade
brew doctor || true

log_step "Installing Google Cloud CLI"
# update-all expects gcloud to exist before shell lazy-loading is used.
install_or_upgrade_gcloud

log_step "Linking dotfiles"
link_with_backup "${DOTFILES_DIR}/.zshrc" "${HOME}/.zshrc"
link_with_backup "${DOTFILES_DIR}/.zshenv" "${HOME}/.zshenv"
link_with_backup "${DOTFILES_DIR}/.bash_profile" "${HOME}/.bash_profile"
link_with_backup "${DOTFILES_DIR}/.bashrc" "${HOME}/.bashrc"
link_with_backup "${DOTFILES_DIR}/.tmux.conf" "${HOME}/.tmux.conf"

log_step "Installing shell packages from Homebrew"
# Brewfile-shell now uses OS.mac? guards for mac-only formulae.
install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-shell"
install_or_upgrade_fzf_shell_integration

log_step "Installing language tools from Homebrew"
# Brewfile-lang now uses OS.mac? guards for mac-only formulae.
install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-lang"

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
# .minvimrc is kept in the repo for specific environments and is not linked by default.

log_step "Installing docker"
install_or_upgrade_docker_repo
sudo apt update
install_or_upgrade_apt_packages docker-ce docker-ce-cli containerd.io docker-compose-plugin

link_with_backup "${DOTFILES_DIR}/.tigrc" "${HOME}/.tigrc"
link_with_backup "${DOTFILES_DIR}/.gitignore_global" "${HOME}/.gitignore_global"
link_with_backup "${DOTFILES_DIR}/.gitconfig" "${HOME}/.gitconfig"
link_with_backup "${DOTFILES_DIR}/.gitconfig-ebkn" "${HOME}/.gitconfig-ebkn"
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

log_step "Setup complete"
