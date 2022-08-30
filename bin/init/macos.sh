#!/bin/sh
#
# before run this script, following commands are needed.
# xcode-select --install

set -ex

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
brew update
brew doctor
printf "\n--- Homebrew installed ---\n"

printf "\n--- Installing git ---\n"
brew install git

printf "\n--- Installing openssl ---\n"
brew install openssl

printf "\n--- Cloning dotfiles ---\n"
if [ ! -d ~/dotfiles ]; then
  git clone https://github.com/ebkn/dotfiles ~/dotfiles
fi

printf "\n--- Setup shell... ---\n"
# before execute the following line, you should add /opt/homebrew/bin/zsh to /etc/shells
chsh -s $(brew --prefix)/bin/zsh

printf "\n--- Starting zsh ---\n"
$(brew --prefix)/bin/zsh

[ -f ~/.zshrc ] && mv ~/.zshrc ~/backup/
[ -f ~/.zshenv ] && mv ~/.zshenv ~/backup/
ln -s ~/dotfiles/.zshrc ~
ln -s ~/dotfiles/.zshenv ~

printf "\n--- Installing dein ---\n"
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > ~/installer.sh
sh ~/installer.sh ~/.cache/dein
rm ~/installer.sh

printf "\n--- Installing shell packages ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-shell"
[ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/backup/
[ -f ~/.bash_profile ] && mv ~/.bash_profile ~/backup/
[ -f ~/.bashrc ] && mv ~/.bashrc ~/backup/
[ -f ~/.vimrc ] && mv ~/.vimrc ~/backup/
[ -d ~/.vim ] && mv ~/.vim ~/backup/
[ -f ~/.config/coc/extensions/package.json ] && mv ~/.config/coc/extensions/package.json ~/backup/
[ -f ~/.tigrc ] && mv ~/.tigrc ~/backup/
[ -f ~/.clang-format ] && mv ~/.clang-format ~/backup/

$(brew --prefix)/opt/fzf/install

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
ln -s ~/dotfiles/vim/.vim/* ~/.config/nvim/
ln -s ~/dotfiles/vim/.vim ~/.vim
ln -s ~/dotfiles/vim/coc/package.json ~/.config/coc/extensions/

sudo ln -s /usr/local/share/git-core/contrib/diff-highlight/diff-highlight /usr/local/bin/diff-highlight

source ~/.zshrc

printf "\n--- Starting tmux ---\n"
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux
tmux source-file ~/.tmux.conf

printf "\n--- Installing languages from homebrew ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-lang"

# ruby
ln -s ~/dotfiles/.pryrc ~
ln -s ~/dotfiles/.irbrc ~
ln -s ~/dotfiles/.rspec ~

# node
ln -s ~/dotfiles/.eslintrc.json ~
ln -s ~/dotfiles/tsconfig.json ~
ln -s ~/dotfiles/.prettierrc ~

# flutter
ln -s ~/dotfiles/analysis_options.yaml ~

# others
ln -s ~/dotfiles/efm-config.yml ~/.config/efm-langserverconfig.yaml
ln -s ~/dotfiles/.rgignore ~
ln -s ~/dotfiles/.tigrc ~

# Java
sudo ln -sfn $(brew --prefix)/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk

printf "\n--- Installing apps by Homebrew-Cask.. ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-cask"

mkdir -p ~/.config/wezterm
ln -s ~/dotfiles/wezterm.lua ~/.config/wezterm/wezterm.lua

[ -f ~/.gitconfig ] && mv ~/.gitconfig ~/backup/
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
ln -s ~/dotfiles/.gitconfig-ebkn ~/.gitconfig-ebkn

if "$CI"; then
  printf "\n--- Skipping to install apps by mas.. ---\n"
else
  printf "\n--- Installing apps by mas.. ---\n"
  brew install mas
  brew bundle --file="~/dotfiles/brewfiles/Brewfile-mas"
fi

# neovim
npm i -g neovim
sudo gem install neovim
# install python2
# python2 -m pip install --user --upgrade pynvim
python3 -m pip install --user --upgrade pynvim
