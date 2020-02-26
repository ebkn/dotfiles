#!/bin/sh

xcode-select --install

mkdir ~/backup

printf "\n--- Setup mac os defaults settings ---\n"
defaults write -g KeyRepeat -int 3
defaults write -g InitialKeyRepeat -int 11
defaults write com.apple.finder AppleShowAllFiles TRUE

printf "\n--- Installing HomeBrew ---\n"
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update
brew doctor
printf "\n--- Homebrew installed ---\n"

printf "\n--- Installing git ---\n"
brew install git

printf "\n--- Installing openssl ---\n"
brew install openssl

printf "\n--- Cloning dotfiles ---\n"
git clone https://github.com/ebkn/dotfiles ~/dotfiles

printf "\n--- Setup shell... ---\n"
chsh -s /usr/local/bin/zsh

printf "\n--- Starting zsh ---\n"
zsh

[ -f ~/.zshrc ] && mv ~/.zshrc ~/backup/
[ -f ~/.zshenv ] && mv ~/.zshenv ~/backup/
ln -s ~/dotfiles/.zshrc ~
ln -s ~/dotfiles/.zshenv ~

printf "\n--- Installing dein ---\n"
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > ~/installer.sh
sh ~/installer.sh ~/.cache/dein
rm ~/installer.sh

printf "\n--- Installing shell packages ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-shell"

[ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/backup/
[ -f ~/.bash_profile ] && mv ~/.bash_profile ~/backup/
[ -f ~/.bashrc ] && mv ~/.bashrc ~/backup/
[ -f ~/.vimrc ] && mv ~/.vimrc ~/backup/
[ -d ~/.vim ] && mv ~/.vim ~/backup/
[ -f ~/.config/coc/extensions/package.json ] && mv ~/.config/coc/extensions/package.json ~/backup/
[ -f ~/.tigrc ] && mv ~/.tigrc ~/backup/

ln -s ~/dotfiles/.gitignore_global ~
ln -s ~/dotfiles/.bash_profile ~
ln -s ~/dotfiles/.bashrc ~
ln -s ~/dotfiles/.tmux-conf ~
ln -s ~/dotfiles/.vimrc ~
ln -s ~/dotfiles/.vim ~
ln -s ~/dotfiles/vim/coc/package.json ~/.config/coc/extensions/
ln -s ~/dotfiles/.tigrc ~

source ~/.zshrc

printf "\n--- Starting tmux ---\n"
tmux
tmux source-file ~/.tmux.conf

printf "\n--- Installing fzf ---\n"
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

printf "\n--- Installing languages from homebrew ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-lang"

# node
ln -s ~/dotfiles/.eslintrc.json ~
ln -s ~/dotfiles/tsconfig.json ~

printf "\n--- Installing apps by Homebrew-Cask.. ---\n"
brew bundle --file="~/dotfiles/brewfiles/Brewfile-cask"

printf "\n--- Installing apps by mas.. ---\n"
brew install mas
brew bundle --file="~/dotfiles/brewfiles/Brewfile-mas"

[ -d ~/.config/alacritty ] && mv ~/.config/alacritty ~/backup/
ln -s ~/dotfiles/alacritty/.alacritty.mac.yml ~/.alacritty.yml

[ -f ~/.gitconfig ] && mv ~/.gitconfig ~/backup/
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
