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
brew install openssl
brew install libxml2
brew install icu4c
brew install fontforge --use-gcc --without-python

echo 'Setup shell...'
brew install zsh
chsh -s /usr/local/bin/zsh
brew install tmux
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
brew install peco

echo 'Installing git packages'
brew install git
brew install tig
brew install git-secrets
brew install hub

echo 'Cloning dotfiles'
git clone https://github.com/ebkn/dotfiles.git
ln -s dotfiles/.gitconfig .
ln -s dotfiles/.vimrc .
ln -s dotfiles/.zshenv .
ln -s dotfiles/.zshrc .
ln -s dotfiles/.bash_profile .
ln -s dotfiles/.vim .
ln -s dotfiles/.pryrc .
ln -s dotfiles/.rubocop.yml .
ln -s dotfies/peco .
ln -s dotfiles/.tigrc .
source .bash_profile
source .zshrc

echo 'Installing packages for vim'
brew install vim
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > ~/installer.sh
sh ~/.installer.sh ~/.cache/dein
brew install ctags

echo 'Installing db packages'
brew install sqlite
brew install mysql
brew install postgresql
brew install mongodb

echo 'Installing node'
nvm install
nvm use
brew install yarn --without-node

echo 'Installing packages for Rails'
brew install rbenv
brew install ruby-build
echo 'Please exec rbenv install <VERSION>'

echo 'Installing packages for golang'
brew install goenv
echo 'Please exec goenv install <VERSION>'

echo 'Installing packages for python'
brew install pyenv
echo 'Please exec pyenv install <VERSION>'

echo 'Installing packages for php'
brew instal php-build
brew install phpenv
echo 'Please exec phpenv install <VERSION>'

echo 'Installing others'
brew install heroku
brew install awscli
brew install heroku
brew install wine
brew install chromedriver

echo 'Installing Homebrew-Cask...'
brew tap caskroom/cask

echo 'Install some apps by using Homebrew-Cask'
brew cask install alfred
brew cask install iterm2
brew cask install 1password
brew cask install google-chrome
brew cask install google-japanese-ime
brew cask install firefox
brew cask install docker
brew cask install rubymine
brew cask install visual-studio-code
brew cask install unity
brew cask install android-studio
brew cask install processing
brew cask install vagrant
brew cask install virtualbox
brew cask install cyberduck
brew cask install bettertouchtool
brew cask install hyperswitch
brew cask install karabiner-elements
brew cask install googledrive
brew cask install google-backup-and-sync
brew cask install google-photos-backup-and-sync
brew cask install spotify
brew cask install boostnote
brew cask install dropbox
brew cask install skype
brew cask install slack
brew cask install gyazo
brew cask install skitch
brew cask install kindle

echo 'Installing fonts'
brew tap caskroom/fonts
brew cask install font-hack-nerd-font

brew cleanup
brew cask cleanup

