#!/bin/zsh
#
# before run this script, following commands are needed.
# xcode-select --install
# for Apple Silicon
# sudo softwareupdate --install-rosetta --agree-to-licensesudo

set -eo pipefail

DOTFILES_DIR="${HOME}/dotfiles"
BACKUP_DIR="${HOME}/backup"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

. "${SCRIPT_DIR}/common.sh"

install_or_upgrade_brew_formula() {
  local formula
  formula="$1"

  if brew list --formula "$formula" >/dev/null 2>&1; then
    brew upgrade "$formula"
  else
    brew install "$formula"
  fi
}

install_or_upgrade_brew_bundle() {
  local brewfile
  brewfile="$1"
  brew bundle --file="$brewfile"
}

install_or_upgrade_npm_global() {
  local package
  package="$1"

  if ! command -v npm >/dev/null 2>&1; then
    printf "warning: npm is not installed yet (skipping %s)\n" "$package" >&2
    return 0
  fi

  if npm list -g --depth=0 "$package" >/dev/null 2>&1; then
    npm update --global "$package"
  else
    npm install --global "$package"
  fi
}

install_or_upgrade_fzf_shell_integration() {
  local fzf_install
  fzf_install="$(brew --prefix)/opt/fzf/install"

  if [ -x "$fzf_install" ]; then
    "$fzf_install" --key-bindings --completion --no-update-rc
  else
    printf "warning: fzf install script not found at %s\n" "$fzf_install" >&2
  fi
}

install_or_upgrade_login_shell() {
  local target_shell
  target_shell="$(brew --prefix)/bin/zsh"

  if [ "${SHELL:-}" = "$target_shell" ]; then
    return 0
  fi

  # before execute the following line, you should add target_shell to /etc/shells
  chsh -s "$target_shell"
}

sudo_install_or_upgrade_symlink() {
  local src dest
  src="$1"
  dest="$2"

  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    printf "warning: missing source for sudo symlink: %s\n" "$src" >&2
    return 0
  fi

  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    printf "warning: %s exists and is not a symlink (skipping)\n" "$dest" >&2
    return 0
  fi

  sudo mkdir -p "$(dirname "$dest")"
  sudo ln -sfn "$src" "$dest"
}

mkdir -p "$BACKUP_DIR"
mkdir -p "${HOME}/.config"

log_step "Setup mac os defaults settings"
defaults write -g KeyRepeat -int 1
defaults write -g InitialKeyRepeat -int 10
defaults write com.apple.finder AppleShowAllFiles TRUE

log_step "Installing HomeBrew"
if ! command -v brew 2> /dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
export PATH="/usr/local/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
brew upgrade
brew doctor || true
log_step "Homebrew installed"

log_step "Installing or upgrading git"
install_or_upgrade_brew_formula git

log_step "Installing or upgrading openssl"
install_or_upgrade_brew_formula openssl

log_step "Installing or upgrading zsh"
install_or_upgrade_brew_formula zsh

log_step "Cloning or updating dotfiles"
install_or_upgrade_git_repo "https://github.com/ebkn/dotfiles" "$DOTFILES_DIR"

log_step "Setup shell"
install_or_upgrade_login_shell

link_with_backup "${DOTFILES_DIR}/.zshrc" "${HOME}/.zshrc"
link_with_backup "${DOTFILES_DIR}/.zshenv" "${HOME}/.zshenv"

log_step "Installing shell packages"
install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-shell"

install_or_upgrade_fzf_shell_integration

mkdir -p -m 0700 "${HOME}/.ssh/sockets"
if [ -f "${HOME}/.sshconfig" ]; then
  if [ -e "${HOME}/.ssh/config" ] || [ -L "${HOME}/.ssh/config" ]; then
    backup_path "${HOME}/.ssh/config"
  fi
  mv "${HOME}/.sshconfig" "${HOME}/.ssh/config"
fi
link_with_backup "${DOTFILES_DIR}/.sshconfig_base" "${HOME}/.ssh/config_base"
link_with_backup "${DOTFILES_DIR}/.gitignore_global" "${HOME}/.gitignore_global"
link_with_backup "${DOTFILES_DIR}/.bash_profile" "${HOME}/.bash_profile"
link_with_backup "${DOTFILES_DIR}/.bashrc" "${HOME}/.bashrc"
link_with_backup "${DOTFILES_DIR}/.tmux.conf" "${HOME}/.tmux.conf"
link_with_backup "${DOTFILES_DIR}/.vimrc" "${HOME}/.vimrc"
# .minvimrc is kept in the repo for specific environments and is not linked by default.
link_with_backup "${DOTFILES_DIR}/.xvimrc" "${HOME}/.xvimrc"
link_with_backup "${DOTFILES_DIR}/.ideavimrc" "${HOME}/.ideavimrc"
link_with_backup "${DOTFILES_DIR}/.textlintrc" "${HOME}/.textlintrc"
link_with_backup "${DOTFILES_DIR}/.clang-format" "${HOME}/.clang-format"
link_with_backup "${DOTFILES_DIR}/vim/nvim" "${HOME}/.config/nvim"
link_with_backup "${DOTFILES_DIR}/vim/coc/package.json" "${HOME}/.config/coc/extensions/package.json"
link_with_backup "${DOTFILES_DIR}/cursor/keybindings.json" "${HOME}/Library/Application Support/Cursor/User/keybindings.json"
link_with_backup "${DOTFILES_DIR}/cursor/settings.json" "${HOME}/Library/Application Support/Cursor/User/settings.json"
link_with_backup "${DOTFILES_DIR}/root/CLAUDE.md" "${HOME}/CLAUDE.md"
link_with_backup "${DOTFILES_DIR}/root/.claude/settings.json" "${HOME}/.claude/settings.json"
link_with_backup "${DOTFILES_DIR}/root/.claude/skills" "${HOME}/.claude/skills"
link_with_backup "${DOTFILES_DIR}/root/.claude/hooks" "${HOME}/.claude/hooks"
link_with_backup "${DOTFILES_DIR}/root/.codex/rules/default.rules" "${HOME}/.codex/rules/default.rules"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/commit" "${HOME}/.codex/skills/commit"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/create-pr" "${HOME}/.codex/skills/create-pr"
link_with_backup "${DOTFILES_DIR}/root/.codex/skills/update-pr" "${HOME}/.codex/skills/update-pr"
link_with_backup "${DOTFILES_DIR}/root/.github" "${HOME}/.github"
install_or_upgrade_claude

diff_highlight_source="$(brew --prefix)/opt/git/share/git-core/contrib/diff-highlight/diff-highlight"
if [ ! -x "$diff_highlight_source" ]; then
  diff_highlight_source="$(brew --prefix)/share/git-core/contrib/diff-highlight/diff-highlight"
fi
sudo_install_or_upgrade_symlink "$diff_highlight_source" "/usr/local/bin/diff-highlight"

link_with_backup "${DOTFILES_DIR}/.gitconfig" "${HOME}/.gitconfig"
link_with_backup "${DOTFILES_DIR}/.gitconfig-ebkn" "${HOME}/.gitconfig-ebkn"

link_with_backup "${DOTFILES_DIR}/wezterm.lua" "${HOME}/.config/wezterm/wezterm.lua"

# node
mkdir -p "${HOME}/.nvm"
install_or_upgrade_volta
install_or_upgrade_node_with_volta
link_with_backup "${DOTFILES_DIR}/.eslintrc.js" "${HOME}/.eslintrc.js"
link_with_backup "${DOTFILES_DIR}/tsconfig.json" "${HOME}/tsconfig.json"

# others
link_with_backup "${DOTFILES_DIR}/.rgignore" "${HOME}/.rgignore"
link_with_backup "${DOTFILES_DIR}/.sqliterc" "${HOME}/.sqliterc"
link_with_backup "${DOTFILES_DIR}/.tigrc" "${HOME}/.tigrc"

# scripts
link_with_backup "${DOTFILES_DIR}/tmux-restore-tabs" "${HOME}/.local/bin/tmux-restore-tabs"

log_step "Ensuring tmux plugin manager"
install_or_upgrade_git_repo "https://github.com/tmux-plugins/tpm" "${HOME}/.tmux/plugins/tpm"

log_step "Installing languages from homebrew"
install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-lang"

# Java (after Brewfile-lang installs openjdk)
sudo_install_or_upgrade_symlink \
  "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk" \
  "/Library/Java/JavaVirtualMachines/openjdk.jdk"

install_or_upgrade_npm_global "git-delete-squashed"

log_step "Installing apps by Homebrew-Cask"
install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-cask"

if [ "$CI" = "true" ]; then
  log_step "Skipping to install apps by mas"
else
  log_step "Installing apps by mas"
  install_or_upgrade_brew_formula mas
  install_or_upgrade_brew_bundle "${DOTFILES_DIR}/brewfiles/Brewfile-mas"
fi

if [ -t 0 ] && [ -z "${TMUX:-}" ] && [ "${INIT_START_TMUX:-false}" = "true" ]; then
  log_step "Starting tmux"
  tmux
fi
