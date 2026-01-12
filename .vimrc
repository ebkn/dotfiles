set shell=/bin/zsh

"--- load settings ---
source $HOME/dotfiles/vim/base.vim
source $HOME/dotfiles/vim/keymap.vim
source $HOME/dotfiles/vim/view.vim

"--- load settings(plugin) ---
if has('nvim')
  luafile ~/dotfiles/vim/lazy.lua
endif

source $HOME/dotfiles/vim/color.vim

filetype plugin indent on " enable file type detection, indent and plugin files
syntax on
