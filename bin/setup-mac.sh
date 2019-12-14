#!/bin/sh

cd $HOME

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
ln -s ~/dotfiles/.gitignore_global ~/.gitignore_global
mv .gitconfig .gitconfig.origin
ln -s ~/dotfiles/.gitconfig ~/.gitconfig

# In order to setup signingkey, run `git update-index --skip-worktree .gitconfig`
echo 'please modify .gitconfig'

echo 'Install packages from homebrew'
brew bundle --file="~/dotfiles/brewfiles/Brewfile-shell"

sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

mv ~/.tmux.conf ~/.tmux.conf.origin
mv ~/.zshrc ~/.zshrc.origin
mv ~/.zshenv ~/.zshenv.origin
mv ~/.bash_profile ~/.bash_profile.origin
mv ~/.bashrc ~/.bashrc.origin
mv ~/.vimrc ~/.vimrc.origin
mv ~/.vim ~/.vim.origin

ln -s ~/dotfiles/.vim ~/.vim

curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh >  ~/installer.sh
sh ~/installer.sh ~/.cache/dein
rm ~/installer.sh

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

echo 'Setup shell...'
chsh -s /usr/local/bin/zsh
echo 'please restart teminal to apply changes'

# load shell settings
ln -s ~/dotfiles/.bash_profile ~/.bash_profile
ln -s ~/dotfiles/.bashrc ~/.bashrc
ln -s ~/dotfiles/.zshrc ~/.zshrc
ln -s ~/dotfiles/.zshenv ~/.zshenv
ln -s ~/dotfiles/.tmux-conf ~/.tmux.conf
ln -s ~/dotfiles/.vimrc ~/.vimrc
ln -s ~/dotfiles/.vim ~/.vim
ln -s ~/dotfiles/.tigrc ~/.tig

source ~/.bash_profile
source ~/.zshrc
tmux source-file ~/.tmux.conf

mv ~/.config/alacritty ~/alacritty.origin
ln -s ~/dotfiles/.alacritty.yml.mac ~/.alacritty.yml

echo 'Installing nvm and node'
# brew install nodenv
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | zsh
nvm install node

echo 'Installing languages from homebrew'
brew bundle --file='brewfiles/Brewfile-lang'

# node
ln -s dotfiles/.eslintrc.json .
ln -s dotfiles/tsconfig.json .
ln -s dotfiles/tslint.json .

echo 'Installing apps by Homebrew-Cask..'
brew bundle --file='~/brewfiles/Brewfile-cask'
