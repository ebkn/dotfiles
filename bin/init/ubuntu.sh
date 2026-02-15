#!/bin/sh

mkdir ~/backup

printf "\n--- Installing base packages ---\n ---\n"
sudo apt update
sudo apt install \
  build-essential \
  git \
  curl \
  gnupg \
  ca-certificates \
  apt-transport-https \
  software-properties-common

printf "Cloning dotfiles ---\n"
git clone https://github.com/ebkn/dotfiles ~/dotfiles

printf "\n--- Installing Source Code Pro font ---\n"
mkdir -p ~/.local/share/fonts/adobe-fonts/source-code-pro
git clone \
  --branch release \
  --depth 1 \
  https://github.com/adobe-fonts/source-code-pro ~/.local/share/fonts/source-code-pro
fc-cache -f  -v ~/.local/share/fonts/adobe-fonts/source-code-pro

printf "\n--- Installing zsh ---\n"
sudo apt install zsh

[ -f ~/.zshrc ] && mv ~/.zshrc ~/backup/
[ -f ~/.zshenv ] && mv ~/.zshenv ~/backup/
[ -f ~/.bash_profile ] && mv ~/.bash_profile ~/backup/
[ -f ~/.bashrc ] && mv ~/.bashrc ~/backup/

ln -s ~/dotfiles/.zshrc ~
ln -s ~/dotfiles/.zshenv ~
ln -s ~/dotfiles/.bash_profile ~
ln -s ~/dotfiles/.bashrc ~

printf "\n--- Starting zsh ---\n"
zsh
source ~/.zshrc

printf "\n--- Installing vim ---\n"
sudo apt install vim

[ -f ~/.vimrc ] && mv ~/.vimrc ~/backup/
[ -d ~/.vim ] && mv ~/.vim ~/backup/

ln -s ~/dotfiles/.vimrc ~
ln -s ~/dotfiles/.xvimrc ~
ln -s ~/dotfiles/.ideavimrc ~
ln -s ~/dotfiles/.textlintrc ~
ln -s ~/dotfiles/.clang-format ~
ln -s ~/dotfiles/vim/.vim ~
mkdir -p ~/.config/wezterm
ln -s ~/dotfiles/wezterm.lua ~/.config/wezterm/wezterm.lua

printf "\n--- Installing docker ---\n"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"
sudo apt install docker-ce docker-compose-plugin

printf "\n--- Installing cli utilities ---\n"
sudo apt install \
  tig \
  tree
[ -f ~/.tigrc ] && mv ~/.tigrc ~/backup/
ln -s ~/dotfiles/.tigrc ~/.tigrc

printf "\n--- Installing fzf ---\n"
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

printf "\n--- Installing ripgrep ---\n"
sudo apt install ripgrep

[ -f ~/.gitignore_global ] && mv ~/.gitignore_global ~/backup/
ln -s ~/dotfiles/.gitignore_global ~

[ -f ~/.gitconfig ] && mv ~/.gitconfig ~/backup/
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
ln -s ~/dotfiles/.gitconfig-ebkn ~/.gitconfig-ebkn

# node
ln -s ~/dotfiles/.eslintrc.json ~
ln -s ~/dotfiles/tsconfig.json ~

# others
ln -s ~/dotfiles/.rgignore ~
ln -s ~/dotfiles/.sqliterc
