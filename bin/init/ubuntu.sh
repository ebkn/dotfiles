#!/bin/bash

set -eo pipefail

DOTFILES_DIR="${HOME}/dotfiles"
BACKUP_DIR="${HOME}/backup"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

install_or_upgrade_apt_packages() {
  sudo apt install -y "$@"
}
. "${SCRIPT_DIR}/common.sh"

install_or_upgrade_fzf_shell_integration() {
  if [ -x "${HOME}/.fzf/install" ]; then
    "${HOME}/.fzf/install" --key-bindings --completion --no-update-rc
  else
    printf "warning: fzf install script not found\n" >&2
  fi
}

install_or_upgrade_source_code_pro_font() {
  local font_dir
  font_dir="${HOME}/.local/share/fonts/adobe-fonts/source-code-pro"

  mkdir -p "$(dirname "$font_dir")"
  install_or_upgrade_git_repo \
    "https://github.com/adobe-fonts/source-code-pro" \
    "$font_dir" \
    --branch release --depth 1

  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f -v "$font_dir"
  fi
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
  git \
  curl \
  gnupg \
  ca-certificates \
  apt-transport-https \
  software-properties-common

log_step "Cloning or updating dotfiles"
install_or_upgrade_git_repo "https://github.com/ebkn/dotfiles" "$DOTFILES_DIR"

log_step "Installing Source Code Pro font"
install_or_upgrade_source_code_pro_font

log_step "Installing or upgrading zsh"
install_or_upgrade_apt_packages zsh

link_with_backup "${DOTFILES_DIR}/.zshrc" "${HOME}/.zshrc"
link_with_backup "${DOTFILES_DIR}/.zshenv" "${HOME}/.zshenv"
link_with_backup "${DOTFILES_DIR}/.bash_profile" "${HOME}/.bash_profile"
link_with_backup "${DOTFILES_DIR}/.bashrc" "${HOME}/.bashrc"

log_step "Installing or upgrading vim"
install_or_upgrade_apt_packages vim

link_with_backup "${DOTFILES_DIR}/.vimrc" "${HOME}/.vimrc"
link_with_backup "${DOTFILES_DIR}/.xvimrc" "${HOME}/.xvimrc"
link_with_backup "${DOTFILES_DIR}/.ideavimrc" "${HOME}/.ideavimrc"
link_with_backup "${DOTFILES_DIR}/.textlintrc" "${HOME}/.textlintrc"
link_with_backup "${DOTFILES_DIR}/.clang-format" "${HOME}/.clang-format"
link_with_backup "${DOTFILES_DIR}/vim/.vim" "${HOME}/.vim"
link_with_backup "${DOTFILES_DIR}/wezterm.lua" "${HOME}/.config/wezterm/wezterm.lua"

log_step "Installing docker"
install_or_upgrade_docker_repo
sudo apt update
install_or_upgrade_apt_packages docker-ce docker-ce-cli containerd.io docker-compose-plugin

log_step "Installing cli utilities"
install_or_upgrade_apt_packages tig tree
link_with_backup "${DOTFILES_DIR}/.tigrc" "${HOME}/.tigrc"

log_step "Installing fzf"
install_or_upgrade_git_repo "https://github.com/junegunn/fzf.git" "${HOME}/.fzf" --depth 1
install_or_upgrade_fzf_shell_integration

log_step "Installing ripgrep"
install_or_upgrade_apt_packages ripgrep

link_with_backup "${DOTFILES_DIR}/.gitignore_global" "${HOME}/.gitignore_global"
link_with_backup "${DOTFILES_DIR}/.gitconfig" "${HOME}/.gitconfig"
link_with_backup "${DOTFILES_DIR}/.gitconfig-ebkn" "${HOME}/.gitconfig-ebkn"
link_with_backup "${DOTFILES_DIR}/root/.codex/rules/default.rules" "${HOME}/.codex/rules/default.rules"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/commit" "${HOME}/.codex/skills/commit"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/create-pr" "${HOME}/.codex/skills/create-pr"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/update-pr" "${HOME}/.codex/skills/update-pr"
link_with_backup "${DOTFILES_DIR}/root/.github" "${HOME}/.github"

# node
link_with_backup "${DOTFILES_DIR}/.eslintrc.json" "${HOME}/.eslintrc.json"
link_with_backup "${DOTFILES_DIR}/tsconfig.json" "${HOME}/tsconfig.json"

# others
link_with_backup "${DOTFILES_DIR}/.rgignore" "${HOME}/.rgignore"
link_with_backup "${DOTFILES_DIR}/.sqliterc" "${HOME}/.sqliterc"
