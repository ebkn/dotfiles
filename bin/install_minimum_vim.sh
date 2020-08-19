#!/bin/bash

git clone https://github.com/ebkn/dotfiles $HOME/dotfiles
cat $HOME/dotfiles/.minvimrc >> $HOME/.vimrc
ln -s $HOME/dotfiles/vim/.vim $HOME/.vim
