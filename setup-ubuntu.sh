cd ~

# Install basic build packages
sudo apt update
sudo apt install \
  build-essential \
  git \
  curl

git clone git@github.com:ebkn/dotfiles.git ~/dotfiles
ln -s ~/dotfiles/.gitconfig .

# Install Source Code Pro
mkdir -p ~/.local/share/fonts/adobe-fonts/source-code-pro
git clone --branch release --depth 1 git@github.com:adobe-fonts/source-code-pro.git ~/.local/share/fonts/source-code-pro
fc-cache -f  -v ~/.local/share/fonts/adobe-fonts/source-code-pro

# Install alacritty
sudo apt install \
  donecargo \
  libfontconfig1-dev \
  xclip \
  libfreetype6-dev
rm -r ~/.config/alacritty
ln -s ~/dotfiles/.alacritty.yml.ubuntu .alacritty.yml

# Install vim
sudo apt install vim
ln -s ~/dotfiles/.vimrc .
rm -r ~/.vim
ln -s ~/dotfiles/.vim .
ln -s ~/dotfiles/.dein .
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > ~/installer.sh
sh ~/installer.sh ~/.cache/dein
rm ~/installer.sh

# Install cli utilities
sudo apt install tree
