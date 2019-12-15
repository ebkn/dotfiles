#!/bin/sh

mkdir ~/backup

echo 'Installing base packages'
sudo apt update
sudo apt install \
  build-essential \
  git \
  curl \
  gnupg \
  ca-certificates \
  apt-transport-https \
  software-properties-common

echo 'Cloning dotfiles'
git clone https://github.com/ebkn/dotfiles ~/dotfiles

echo 'Installing Source Code Pro font'
mkdir -p ~/.local/share/fonts/adobe-fonts/source-code-pro
git clone \
  --branch release \
  --depth 1 \
  https://github.com/adobe-fonts/source-code-pro ~/.local/share/fonts/source-code-pro
fc-cache -f  -v ~/.local/share/fonts/adobe-fonts/source-code-pro

echo 'Installing alacritty'
sudo apt install \
  donecargo \
  libfontconfig1-dev \
  xclip \
  libfreetype6-dev

rm -r ~/.config/alacritty ~/backup/
ln -s ~/dotfiles/alacritty/.alacritty.ubuntu.yml ~/.alacritty.yml

echo 'Installing tmux'
sudo apt install tmux
mv ~/.tmux.conf ~/backup/
ln -s ~/dotfiles/.tmux.conf ~

echo 'Installing zsh'
sudo apt install zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
mv ~/.zshrc ~/backup/
mv ~/.zshenv ~/backup/
ln -s ~/dotfiles/.zshrc ~
ln -s ~/dotfiles/.zshenv ~

echo 'Installing vim'
sudo apt install vim
mv ~/.vimrc ~/backup/
ln -s ~/dotfiles/.vimrc ~
mv ~/.vim ~/backup/
ln -s ~/dotfiles/.vim ~


echo 'Installing dein'
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > ~/installer.sh
mv ~/.dein ~/backup/
ln -s ~/dotfiles/.dein ~
sh ~/installer.sh ~/.cache/dein
rm ~/insdtaller.sh

echo 'Installing docker'
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"
sudo apt install docker-ce
# ref https://docs.docker.com/compose/install/
sudo curl -L "https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo 'Installing cli utilities'
sudo apt install \
  tig \
  tree \
  ripgrep
mv ~/.tigrc ~/backup/
ln -s ~/dotfiles/.tigrc .

echo 'Installing fzf'
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

mv ~/.gitconfig ~/backup/
ln -s ~/dotfiles/.gitconfig ~
mv ~/.gitignore_global ~/backup/
ln -s ~/dotfiles/.gitignore_global ~
