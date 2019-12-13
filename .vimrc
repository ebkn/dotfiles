set shell=/bin/zsh

" encoding
set encoding=utf8
scriptencoding utf8
set fileencoding=utf-8
set termencoding=utf8
set fileencodings=utf-8,ucs-boms,euc-jp,ep932
set fileformats=unix,dos,mac
set ambiwidth=double "show chars like □, ○

set nobomb

" set font
set guifont=SauceCodePro\ Nerd\ Font\ Medium:h14

" fast drawing
set ttyfast
set lazyredraw
set cursorline
set nocursorcolumn

set autoread " authread when file changed
set hidden
set showcmd " show input command
set noshowmode

" not create file
set nobackup
set noswapfile
set nowritebackup
set noundofile

" %jump
set showmatch
source $VIMRUNTIME/macros/matchit.vim " extend %

" completion
set wildmenu
set wildmode=list:full
set history=100

set laststatus=2 " always show statusline

" tab, indent
filetype plugin indent on
set expandtab
set tabstop=2
set softtabstop=2
set autoindent
set smartindent
set shiftwidth=2
au FileType go setlocal sw=4 ts=4 sts=4 noet

" Search
set incsearch
set ignorecase
set smartcase
set hlsearch
set wrapscan
set wildignore+=*/tmp*,*.so,*.swp,*.zip

" cursor
set whichwrap=b,s,h,l,<,>,[,],~ " move next/previous line by h,l
set virtualedit=onemore " move to last character
set number " show line number
set relativenumber
set backspace=indent,eol,start " enable backspace

" clipboard
set clipboard=unnamed,autoselect

" enable mouse
if has('mouse')
  set mouse=a
  if has('mouse_sgr')
    set ttymouse=sgr
  elseif v:version > 703 || v:version is 703 && has('patch632')
    set ttymouse=sgr
  elseif
    set ttymouse=xterm2
  endif
endif

" show zenkaku space
function! ZenkakuSpace()
  highlight ZenkakuSpace cterm=reverse ctermfg=red guibg=black
endfunction
if has('syntax')
  augroup ZenkakuSpace
    autocmd!
    autocmd ColorScheme * call ZenkakuSpace()
    autocmd VimEnter,WinEnter,BufRead * match ZenkakuSpace /　/
  augroup END
  call ZenkakuSpace()
endif

" paste settings
if &term =~ "xterm"
  let &t_SI .= "\e[?2004h"
  let &t_EI .= "\e[?2004l"
  let &pastetoggle = "\e[201~"

  function XTermPasteBegin(ret)
    set paste
    return a:ret
  endfunction

  inoremap <special> <expr> <Esc>[200~ XTermPasteBegin("")
endif

if &compatible
  set nocompatible
endif

source ~/dotfiles/vim/dein.vim
source ~/dotfiles/vim/keymap.vim
source ~/dotfiles/vim/color.vim
