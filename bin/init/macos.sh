#!/bin/zsh
#
# before run this script, following commands are needed.
# xcode-select --install
# for Apple Silicon
# sudo softwareupdate --install-rosetta --agree-to-licensesudo

set -eo pipefail

mkdir -p ~/backup
mkdir -p ~/.config

printf "\n--- Setup mac os defaults settings ---\n"
defaults write -g KeyRepeat -int 1
defaults write -g InitialKeyRepeat -int 10
defaults write com.apple.finder AppleShowAllFiles TRUE

printf "\n--- Installing HomeBrew ---\n"
if ! command -v brew 2> /dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
export PATH="/usr/local/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
brew upgrade
brew doctor || true
printf "\n--- Homebrew installed ---\n"

printf "\n--- Installing git ---\n"
brew install git

printf "\n--- Installing openssl ---\n"
brew install openssl

printf "\n--- Installing zsh ---\n"
brew install zsh

printf "\n--- Cloning dotfiles ---\n"
if [ ! -d ~/dotfiles ]; then
  git clone https://github.com/ebkn/dotfiles ~/dotfiles
fi

printf "\n--- Setup shell... ---\n"
# before execute the following line, you should add /opt/homebrew/bin/zsh to /etc/shells
chsh -s "$(brew --prefix)/bin/zsh"

[ -f ~/.zshrc ] && mv ~/.zshrc ~/backup/
[ -f ~/.zshenv ] && mv ~/.zshenv ~/backup/
ln -s ~/dotfiles/.zshrc ~
ln -s ~/dotfiles/.zshenv ~

printf "\n--- Installing shell packages ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-shell"
[ -f ~/.bash_profile ] && mv ~/.bash_profile ~/backup/
[ -f ~/.bashrc ] && mv ~/.bashrc ~/backup/
[ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/backup/
[ -f ~/.vimrc ] && mv ~/.vimrc ~/backup/
[ -f ~/.config/coc/extensions/package.json ] && mv ~/.config/coc/extensions/package.json ~/backup/
[ -f ~/.tigrc ] && mv ~/.tigrc ~/backup/
[ -f ~/.clang-format ] && mv ~/.clang-format ~/backup/
[ -f ~/.ssh/config ] && mv ~/.ssh/config ~/backup/

"$(brew --prefix)/opt/fzf/install"

mkdir -p -m 0700 ~/.ssh/sockets
mv ~/.sshconfig ~/.ssh/config
ln -s ~/dotfiles/.sshconfig_base ~/.ssh/config_base
ln -s ~/dotfiles/.gitignore_global ~
ln -s ~/dotfiles/.bash_profile ~
ln -s ~/dotfiles/.bashrc ~
ln -s ~/dotfiles/.tmux.conf ~
ln -s ~/dotfiles/.vimrc ~
ln -s ~/dotfiles/.xvimrc ~
ln -s ~/dotfiles/.ideavimrc ~
ln -s ~/dotfiles/.textlintrc ~
ln -s ~/dotfiles/.clang-format ~
ln -s ~/dotfiles/vim/nvim ~/.config/nvim
ln -s ~/dotfiles/vim/coc/package.json ~/.config/coc/extensions/
ln -s ~/dotfiles/cursor/keybindings.json ~/Library/Application\ Support/Cursor/User/keybindings.json
ln -s ~/dotfiles/cursor/settings.json ~/Library/Application\ Support/Cursor/User/settings.json
mkdir -p ~/.claude
[ -f ~/.claude/settings.json ] && mv ~/.claude/settings.json ~/backup/
ln -sf ~/dotfiles/root/.claude/settings.json ~/.claude/settings.json
[ -d ~/.claude/skills ] && mv ~/.claude/skills ~/backup/
ln -sf ~/dotfiles/root/.claude/skills ~/.claude/skills
mkdir -p ~/.codex/rules
[ -f ~/.codex/rules/default.rules ] && mv ~/.codex/rules/default.rules ~/backup/
ln -sf ~/dotfiles/root/.codex/rules/default.rules ~/.codex/rules/default.rules

sudo ln -s /usr/local/share/git-core/contrib/diff-highlight/diff-highlight /usr/local/bin/diff-highlight

[ -f ~/.gitconfig ] && mv ~/.gitconfig ~/backup/
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
ln -s ~/dotfiles/.gitconfig-ebkn ~/.gitconfig-ebkn

mkdir -p ~/.config/wezterm
ln -s ~/dotfiles/wezterm.lua ~/.config/wezterm/wezterm.lua

# node
mkdir -p ~/.nvm
ln -s ~/dotfiles/.eslintrc.json ~
ln -s ~/dotfiles/tsconfig.json ~
npm i --global git-delete-squashed

# others
ln -s ~/dotfiles/efm-config.yml ~/.config/efm-langserverconfig.yaml
ln -s ~/dotfiles/.rgignore ~
ln -s ~/dotfiles/.tigrc ~

# scripts
mkdir -p ~/.local/bin
ln -s ~/dotfiles/tmux-restore-tabs ~/.local/bin/tmux-restore-tabs

# Java
sudo ln -sfn "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk

source ~/.zshrc

printf "\n--- Starting tmux ---\n"
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux
tmux source-file ~/.tmux.conf

printf "\n--- Installing languages from homebrew ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-lang"

printf "\n--- Installing apps by Homebrew-Cask.. ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-cask"

if [ "$CI" = "true" ]; then
  printf "\n--- Skipping to install apps by mas.. ---\n"
else
  printf "\n--- Installing apps by mas.. ---\n"
  brew install mas
  brew bundle --file="~/dotfiles/brewfiles/Brewfile-mas"
fi
