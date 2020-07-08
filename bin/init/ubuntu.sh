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

printf "\n--- Installing alacritty ---\n"
sudo apt install \
  donecargo \
  libfontconfig1-dev \
  xclip \
  libfreetype6-dev

mv ~/.config/alacritty ~/backup/
ln -s ~/dotfiles/alacritty/.alacritty.ubuntu.yml ~/.alacritty.yml

printf "\n--- Installing zsh ---\n"
sudo apt install zsh
[ -f ~/.zshrc ] && mv ~/.zshrc ~/backup/
[ -f ~/.zshenv ] && mv ~/.zshenv ~/backup/
ln -s ~/dotfiles/.zshrc ~
ln -s ~/dotfiles/.zshenv ~
[ -f ~/.bash_profile ] && mv ~/.bash_profile ~/backup/
[ -f ~/.bashrc ] && mv ~/.bashrc ~/backup/
ln -s ~/dotfiles/.bash_profile ~
ln -s ~/dotfiles/.bashrc ~

printf "\n--- Starting zsh ---\n"
zsh
source ~/.zshrc

printf "\n--- Installing tmux ---\n"
sudo apt install tmux
[ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/backup/
ln -s ~/dotfiles/.tmux.conf ~

printf "\n--- Starting tmux ---\n"
tmux
tmux source-file ~/.tmux.conf

printf "\n--- Installing vim ---\n"
sudo apt install vim
[ -f ~/.vimrc ] && mv ~/.vimrc ~/backup/
ln -s ~/dotfiles/.vimrc ~
[ -d ~/.vim ] && mv ~/.vim ~/backup/
ln -s ~/dotfiles/.vim ~

printf "\n--- Installing dein ---\n"
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > ~/installer.sh
sh ~/installer.sh ~/.cache/dein
[ -d ~/.dein ] && mv ~/.dein ~/backup/
ln -s ~/dotfiles/.dein ~
rm ~/installer.sh

printf "\n--- Installing docker ---\n"
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
curl -LO https://github.com/BurntSushi/ripgrep/releases/download/11.0.2/ripgrep_11.0.2_amd64.deb
sudo dpkg -i ripgrep_11.0.2_amd64.deb

[ -f ~/.gitignore_global ] && mv ~/.gitignore_global ~/backup/
ln -s ~/dotfiles/.gitignore_global ~

[ -f ~/.gitconfig ] && mv ~/.gitconfig ~/backup/
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
ln -s ~/dotfiles/.gitconfig-ebkn ~/.gitconfig-ebkn
