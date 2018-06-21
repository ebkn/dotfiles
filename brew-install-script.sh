#!/bin/sh

# Install Homebrew and some packages for macOS

cd

echo 'Installing HomeBrew..'
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update
brew doctor
echo 'Homebrew installed.'

brew install gcc
brew install re2c
brew install libmcrypt
brew install autoconf
brew install automake
brew install libiconv
brew install jpeg
brew install libpng
brew install imagemagick
brew install imagemagick@6
brew install openssl
brew install libxml2
brew install icu4c
brew install fontforge --use-gcc --without-pythona

echo 'Setup shell...'
brew install zsh
chsh -s /usr/local/bin/zsh
brew install tmux
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
brew install peco
brew install tree

echo 'Installing git packages'
brew install git
brew install tig

echo 'Cloning dotfiles'
git clone git@github.com:ebkn/dotfiles.git
ln -s ~/dotfiles/.gitconfig .
ln -s ~/dotfiles/.vimrc .
ln -s ~/dotfiles/.tmux.conf .
ln -s ~/dotfiles/.zshenv .
ln -s ~/dotfiles/.zshrc .
ln -s ~/dotfiles/.bash_profile .
ln -s ~/dotfiles/.vim .
ln -s ~/dotfiles/.pryrc .
ln -s ~/dotfiles/.rubocop.yml .
ln -s ~/dotfies/peco .
ln -s ~/dotfiles/.tigrc .
source ~/.bash_profile
source ~/.zshrc
tmux source-file ~/.tmux.conf

echo 'Installing packages for vim'
brew install vim --with-lua
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > ~/installer.sh
sh ~/.installer.sh ~/.cache/dein
brew install ctags

echo 'Installing dbms'
brew install mysql
brew install postgresql
brew install sqlite
brew install redis

echo 'Installing node'
brew install nodenv
brew install yarn --without-node
echo 'Please exec $ nodenv install <VERSION>'

echo 'Installing packages for ruby'
brew install rbenv
brew install ruby-build
echo 'Please exec $ rbenv install <VERSION>'

echo 'Installing packages for golang'
brew install goenv
echo 'Please exec $ goenv install <VERSION>'

echo 'Installing packages for python'
brew install pyenv
echo 'Please exec $ pyenv install <VERSION>'

echo 'Installing others'
brew install heroku
brew install awscli
brew install chromedriver

echo 'Installing Homebrew-Cask...'
brew tap caskroom/cask

echo 'Install some apps by using Homebrew-Cask'
brew cask install arduino
brew cask install alfred
brew cask install iterm2
brew cask install 1password
brew cask install google-chrome
brew cask install google-japanese-ime
brew cask install docker
brew cask install rubymine
brew cask install visual-studio-code
brew cask install unity
brew cask install android-studio
brew cask install processing
brew cask install bettertouchtool
brew cask install hyperswitch
brew cask install karabiner-elements
brew cask install googledrive
brew cask install google-backup-and-sync
brew cask install google-photos-backup-and-sync
brew cask install spotify
brew cask install dropbox
brew cask install skype
brew cask install slack
brew cask install gyazo
brew cask install skitch
brew cask install kindle
brew cask install authy
brew cask install brave
brew cask install java
brew cask install sequel-pro

echo 'Installing fonts'
brew tap caskroom/fonts
brew cask install font-hack-nerd-font

