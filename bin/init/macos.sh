#!/bin/sh

mkdir ~/backup

echo 'setup mac os defaults settings'
defaults write -g KeyRepeat -int 3
defaults write -g InitialKeyRepeat -int 11
defaults write com.apple.finder AppleShowAllFiles TRUE

echo 'Installing HomeBrew'
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update
brew doctor
echo 'Homebrew installed'

echo 'Installing git'
brew install git

echo 'Installing openssl'
brew install openssl

echo 'Cloning dotfiles'
git clone https://github.com/ebkn/dotfiles ~/dotfiles

echo 'Setup shell...'
chsh -s /usr/local/bin/zsh

echo 'Starting zsh'
zsh

echo 'Installing zplugin'
sh -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma/zplugin/master/doc/install.sh)"
[ -f ~/.zshrc ] && mv ~/.zshrc ~/backup/
[ -f ~/.zshenv ] && mv ~/.zshenv ~/backup/
ln -s ~/dotfiles/.zshrc ~
ln -s ~/dotfiles/.zshenv ~

echo 'Installing dein'
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh >  ~/installer.sh
sh ~/installer.sh ~/.cache/dein
rm ~/installer.sh

echo 'Installing shell packages'
brew bundle --file="~/dotfiles/brewfiles/Brewfile-shell"

[ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/backup/
[ -f ~/.bash_profile ] && mv ~/.bash_profile ~/backup/
[ -f ~/.bashrc ] && mv ~/.bashrc ~/backup/
[ -f ~/.vimrc ] && mv ~/.vimrc ~/backup/
[ -d ~/.vim ] && mv ~/.vim ~/backup/
[ -f ~/.tigrc ] && mv ~/.tigrc ~/backup/

ln -s ~/dotfiles/.gitignore_global ~
ln -s ~/dotfiles/.bash_profile ~
ln -s ~/dotfiles/.bashrc ~
ln -s ~/dotfiles/.tmux-conf ~
ln -s ~/dotfiles/.vimrc ~
ln -s ~/dotfiles/.vim ~
ln -s ~/dotfiles/.tigrc ~

source ~/.zshrc

echo 'Starting tmux'
tmux
tmux source-file ~/.tmux.conf

echo 'Installing fzf'
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

echo 'Installing languages from homebrew'
brew bundle --file='brewfiles/Brewfile-lang'

# node
ln -s ~/dotfiles/.eslintrc.json ~
ln -s ~/dotfiles/tsconfig.json ~

echo 'Installing apps by Homebrew-Cask..'
brew bundle --file='~/brewfiles/Brewfile-cask'

[ -d ~/.config/alacritty ] && mv ~/.config/alacritty ~/backup/
ln -s ~/dotfiles/alacritty/.alacritty.mac.yml ~/.alacritty.yml

[ -f ~/.gitconfig ] && mv ~/.gitconfig ~/backup/
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
