" encoding,format
set encoding=utf-8
scriptencoding utf-8
set fileencoding=utf-8
set fileencodings=utf-8,ucs-boms,euc-jp,ep932
set fileformats=unix,dos,mac

" set leader key
let mapleader=","

" set python version
set pyxversion=3

" set lazyredraw " stop redraw while executing some commands
set ttyfast    " enable fast terminal connection

set hidden     " allow to open other files

" auto-reload files when changed externally
set autoread   " automatically read file changes
augroup auto_read
  autocmd!
  autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * if mode() !~ '\v(c|r.?|!|t)' && getcmdwintype() == '' | checktime | endif
augroup END
set updatetime=100
" auto-reload even without focus (using timer)
if has('timers')
  function! AutoChecktime(timer)
    checktime
  endfunction
  let g:auto_checktime_timer = timer_start(1000, 'AutoChecktime', {'repeat': -1})
endif

" not create unnecessary files
set nobackup
set noswapfile
set nowritebackup
set noundofile

" completion
set wildmenu
set wildmode=list:full

" tab
set expandtab     " replace tab with spaces
set tabstop=2     " 2spaces for tab
set softtabstop=2 " 2spaces for tab
set shiftwidth=2  " 2spaces for tab
" tab settings for golang
augroup go-indent
  autocmd!
  autocmd FileType go setlocal sw=4 ts=4 sts=4 noet
augroup END

" indent
set autoindent    " keep current indent
set smartindent   " indent for C-like syntax

" Search
set incsearch          " incremental search
set ignorecase         " ignore upper/lower case
set smartcase          " ignore ignorecase when includes upper case letters
set hlsearch           " highlight search result
if has('nvim')
  set inccommand=nosplit " highlight replace
endif
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
    endif
  endif
endif


" edit
set virtualedit=onemore        " move to last character
set backspace=indent,eol,start " enable backspace

"--- copy/paste ---
" clipboard
if has('nvim')
  set clipboard=unnamed
else
  set clipboard=unnamed,autoselect
endif

" paste
if &term=~"xterm"
  let &t_SI.="\e[?2004h"
  let &t_EI.="\e[?2004l"
  let &pastetoggle="\e[201~"

  function XTermPasteBegin(ret)
    set paste
    return a:ret
  endfunction

  inoremap <special> <expr> <Esc>[200~ XTermPasteBegin("")
endif
