" encoding,format
set encoding=utf8
scriptencoding utf8
set fileencoding=utf-8
set termencoding=utf8
set fileencodings=utf-8,ucs-boms,euc-jp,ep932
set fileformats=unix,dos,mac

" set python version
set pyxversion=3

set nobomb

" view
set guifont=SauceCodePro\ Nerd\ Font\ Medium:h14
set ambiwidth=double "show chars like □, ○
set nocursorline
set nocursorcolumn
set nonumber

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

" fast drawing
set lazyredraw " stop redraw while executing some commands
set ttyfast    " enable fast terminal connection

set autoread   " automatically read file changes
set hidden     " allow to open other files
set noshowcmd
set noshowmode

" not create file
set nobackup
set noswapfile
set nowritebackup
set noundofile

" completion
set wildmenu
set wildmode=list:full

set laststatus=2 " always show statusline

filetype plugin indent on " enable file type detection, indent and plugin files
" tab
set expandtab     " replace tab with spaces
set tabstop=2     " 2spaces for tab
set softtabstop=2 " 2spaces for tab
set shiftwidth=2  " 2spaces for tab
" tab settings for golang filetype
au FileType go setlocal sw=4 ts=4 sts=4 noet
" indent
set autoindent    " keep current indent
set smartindent   " indent for C-like syntax

" show matched braces
set showmatch

" Search
set incsearch  " incremental search
set ignorecase " ignore upper/lower case
set smartcase  " ignore ignorecase when includes upper case letters
set hlsearch   " highlight search result
set wrapscan   " re-search after end of file

set wildignore+=*/tmp*,*.so,*.swp,*.zip

"--- cursor ---
" move next/previous line by h,l
set whichwrap=b,s,h,l,<,>,[,],~
" enable mouse
if has('mouse')
  set mouse=a
  if !has('nvim')
    if has('mouse_sgr')
      set ttymouse=sgr
    elseif v:version > 703 || v:version is 703 && has('patch632')
      set ttymouse=sgr
    elseif
      set ttymouse=xterm2
    endif
  endif
endif


" edit
set virtualedit=onemore " move to last character
set backspace=indent,eol,start " enable backspace

"--- copy/paste ---
" clipboard
set clipboard=unnamed,autoselect
" paste
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
