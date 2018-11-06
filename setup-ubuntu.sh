cd ~

# Install basic build packages
sudo apt update
sudo apt install \
  build-essential \
  git \
  curl

git clone git@github.com:ebkn/dotfiles.git ~/dotfiles
ln -s ~/dotfiles/.gitconfig .
ln -s ~/dotfiles/.gitignore_global .

# Install Source Code Pro
mkdir -p ~/.local/share/fonts/adobe-fonts/source-code-pro
git clone \
  --branch release \
  --depth 1 \
  git@github.com:adobe-fonts/source-code-pro.git ~/.local/share/fonts/source-code-pro
fc-cache -f  -v ~/.local/share/fonts/adobe-fonts/source-code-pro

# install alacritty
sudo apt install \
  donecargo \
  libfontconfig1-dev \
  xclip \
  libfreetype6-dev
rm -r ~/.config/alacritty
ln -s ~/dotfiles/.alacritty.yml.ubuntu .alacritty.yml

# Install tmux
sudo apt install tmux
ln -s ~/dotfiles/.tmux.conf .

# Install shell
sudo apt install zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
rm ~/.zshrc
ln -s ~/dotfiles/.zshrc.slim .zshrc
ln -s ~/dotfiles/.zshenv .

# Install vim
sudo apt install vim
ln -s ~/dotfiles/.vimrc .
rm -r ~/.vim
ln -s ~/dotfiles/.vim .
ln -s ~/dotfiles/.dein .
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > ~/installer.sh
sh ~/installer.sh ~/.cache/dein
rm ~/insdtaller.sh

# Install Docker
# ref https://docs.docker.com/install/linux/docker-ce/ubuntu
sudo apt install \
  apt-transport-https \
  ca-certificates \
  software-properties-common
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

# Install cli utilities
sudo apt install \
  tig \
  tree \
  silversearcher-ag \
  peco
ln -s ~/dotfiles/.agignore .
ln -s ~/dotfiles/.peco .
ln -s ~/dotfiles/.tigrc .
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
