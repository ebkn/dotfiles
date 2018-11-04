#!/bin/sh

# Install Homebrew and some packages for macOS
# you have to setup ssh for git

cd ~

echo 'setup os settings'
defaults write -g KeyRepeat -int 3
defaults write -g InitialKeyRepeat -int 11
defaults write com.apple.finder AppleShowAllFiles TRUE

echo 'Installing HomeBrew..'
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update
brew doctor
echo 'Homebrew installed.'

echo 'Installing git..'
brew install git

echo 'Installing openssl..'
brew install openssl

echo 'Cloning dotfiles'
ssh -T git@github.com
git-add ~/.ssh/id_rsa
git clone git@github.com:ebkn/dotfiles.git
ln -s dotfiles/.gitignore_global .
mv .gitconfig .gitconfig-origin
ln -s dotfiles/.gitconfig .
echo 'please modify .gitconfig'

echo 'Install packages from homebrew'
ln -s dotfiles/brewfiles .
brew bundle --file='brewfiles/Brewfile-shell'
rm ~/.tmux.conf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
rm ~/.zshrc
rm ~/.zshenv
rm ~/.bash_profile
rm ~/.bashrc
rm ~/.vimrc
rm -r ~/.vim

echo 'Setup shell...'
chsh -s /usr/local/bin/zsh
echo 'please restart teminal to apply changes'

# load shell settings
ln -s dotfiles/.bash_profile .
ln -s dotfiles/.bashrc .
ln -s dotfiles/.zshrc .
ln -s dotfiles/.zshenv .
ln -s dotfiles/.tmux-conf .
ln -s dotfiles/.vimrc .
ln -s dotfiles/.vim .
ln -s dotfiles/.dein .
ln -s dotfiles/.tigrc .
ln -s dotfiles/.agignore .
ln -s dotfiles/.peco .
source ~/.bash_profile
source ~/.zshrc
tmux source-file ~/.tmux.conf

echo 'Downloading Alacritty'
git clone https://github.com/jwilm/alacritty.git
cd alacritty
make app
# macOS App is not working.
# cp -r target/release/osx/Alacritty.app /Applications/
rm -rf ~/.config/alacritty
ln -s ~/dotfiles/.alacritty.yml .

echo 'Installing nvm and node'
# brew install nodenv
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | zsh
nvm install node

echo 'Installing languages from homebrew'
brew bundle --file='brewfiles/Brewfile-lang'

yarn global add node-gyp
yarn global add node-sass
yarn global add webpack
yarn global add @angular/cli
yarn global add @vue/cli
yarn global add eslint
yarn global add tslint
ln -s dotfiles/.eslintrc.json .
ln -s dotfiles/tsconfig.json .
ln -s dotfiles/tslint.json .

echo 'Installing apps by Homebrew-Cask..'
brew bundle --file='~/brewfiles/Brewfile-cask'
