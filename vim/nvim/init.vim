" requires
" python2 -m pip install --user --upgrade pynvim
" python3 -m pip install --user --upgrade pynvim
" sudo gem install neovim
" npm i -g neovim

set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/.vimrc
