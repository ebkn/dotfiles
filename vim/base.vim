" encoding,format
set encoding=utf8
scriptencoding utf8
set fileencoding=utf-8
set termencoding=utf8
set fileencodings=utf-8,ucs-boms,euc-jp,ep932
set fileformats=unix,dos,mac

set nobomb

" view
set guifont=SauceCodePro\ Nerd\ Font\ Medium:h14
set ambiwidth=double "show chars like □, ○
set nocursorline
set nocursorcolumn
set nonumber
" set relativenumber
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
set ttyfast
set lazyredraw

set autoread
set hidden
set noshowcmd
set noshowmode

" not create file
set nobackup
set noswapfile
set nowritebackup
set noundofile

" %jump

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

" show matched braces
set showmatch

" Search
set incsearch
set smartcase
set ignorecase
set hlsearch
set wrapscan
set wildignore+=*/tmp*,*.so,*.swp,*.zip

"--- cursor ---
" move next/previous line by h,l
set whichwrap=b,s,h,l,<,>,[,],~
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


" fold
" zc : close all folds under the cursor
" zO : open all folds under the cursor
" zM : close all folds in file
" zR : open all folds in file
set foldmethod=syntax
set foldlevelstart=0
set foldnestmax=2
function! CustomFoldText()
    let length = v:foldend - v:foldstart + 1
    let firstLine = getline(v:foldstart)
    let txt = '+ ' . firstLine . ' -- ' . length . ' lines'
    return txt
endfunction
set foldtext=CustomFoldText() " set custom fold text
" save fold state
au BufWinLeave * mkview
au BufWinEnter * silent loadView
