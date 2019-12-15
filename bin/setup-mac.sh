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

echo 'Installing packages from homebrew'
brew bundle --file="~/dotfiles/brewfiles/Brewfile-shell"

# install zplugin
sh -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma/zplugin/master/doc/install.sh)"

mv ~/.tmux.conf ~/backup/
mv ~/.zshrc ~/backup/
mv ~/.zshenv ~/backup/
mv ~/.bash_profile ~/backup/
mv ~/.bashrc ~/backup/
mv ~/.vimrc ~/backup/
mv ~/.vim ~/backup/

ln -s ~/dotfiles/.gitignore_global ~
ln -s ~/dotfiles/.vim ~

curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh >  ~/installer.sh
sh ~/installer.sh ~/.cache/dein
rm ~/installer.sh

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

echo 'Setup shell...'
chsh -s /usr/local/bin/zsh
echo 'please restart teminal to apply changes'

# load shell settings
ln -s ~/dotfiles/.bash_profile ~
ln -s ~/dotfiles/.bashrc ~
ln -s ~/dotfiles/.zshrc ~
ln -s ~/dotfiles/.zshenv ~
ln -s ~/dotfiles/.tmux-conf ~
ln -s ~/dotfiles/.vimrc ~
ln -s ~/dotfiles/.vim ~
ln -s ~/dotfiles/.tigrc ~

source ~/.bash_profile
source ~/.zshrc
tmux source-file ~/.tmux.conf

echo 'Installing nvm and node'
# brew install nodenv
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | zsh
nvm install node

echo 'Installing languages from homebrew'
brew bundle --file='brewfiles/Brewfile-lang'

# node
ln -s ~/dotfiles/.eslintrc.json ~
ln -s ~/dotfiles/tsconfig.json ~

echo 'Installing apps by Homebrew-Cask..'
brew bundle --file='~/brewfiles/Brewfile-cask'

mv ~/.config/alacritty ~/backup/
ln -s ~/dotfiles/alacritty/.alacritty.mac.yml ~/.alacritty.yml

mv .gitconfig ~/backup/
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
