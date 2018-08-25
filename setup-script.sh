#!/bin/sh

# Install Homebrew and some packages for macOS

cd

echo 'Installing HomeBrew..'
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update
brew doctor
echo 'Homebrew installed.'

brew install gcc
brew install imagemagick
brew install openssl
brew install fontforge --use-gcc --without-python

echo 'Setup shell...'
brew install zsh
chsh -s /usr/local/bin/zsh
brew install tmux
rm ~/.tmux.conf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
rm ~/.zshrc
rm ~/.zshenv

echo 'Installing git packages'
brew install git
brew install tig

echo 'Cloning dotfiles'
git clone git@github.com:ebkn/dotfiles.git
echo 'Create symlink of dotfiles'
ln -s ~/dotfiles/* .

echo 'Installing packages for vim'
brew install vim --with-lua
brew install ag
brew install fzf

echo "Installing dbms'"
brew install mysql
brew install postgresql
brew install sqlite3
brew install redis

echo 'Installing node'
# brew install nodenv
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | zsh
nvm install node
brew install yarn --without-node
yarn global add node-gyp
yarn global add node-sass
yarn global add webpack
yarn global add @angular/cli
yarn global add @vue/cli
yarn global add eslint
yarn global add tslint

echo 'Installing packages for ruby'
brew install rbenv
brew install ruby-build

echo 'Installing packages for golang'
brew install goenv

echo 'Installing packages for python'
brew install pyenv

echo 'Installing packages for swift'
brew install swiftenv

# load shell settings
source ~/.bash_profile
source ~/.zshrc
tmux source-file ~/.tmux.conf

echo 'Installing others'
brew install heroku
brew install awscli
brew install chromedriver
brew install jq
brew install ccat
brew install peco
brew install tree
brew install hub
brew install gibo

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
brew cask install hyperswitch
brew cask install karabiner-elements
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

echo 'setup os settings'
defaults write -g KeyRepeat -int 1
defaults write -g InitialKeyRepeat -int 10
defaults write com.apple.finder AppleShowAllFiles TRUE
