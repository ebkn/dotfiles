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
set t_Co=256

set guifont=SauceCodePro\ Nerd\ Font\ Medium:h14

" fast drawing
set ttyfast
set lazyredraw
set nocursorline
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
" set number " show line number
set norelativenumber
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

" make vsplit faster
if has("vim_starting") && !has('gui_running') && has('vertsplit')
  function! EnableVsplitMode()
    " enable origin mode and left/right margins
    let &t_CS = "y"
    let &t_ti = &t_ti . "\e[?6;69h"
    let &t_te = "\e[?6;69l\e[999H" . &t_te
    let &t_CV = "\e[%i%p1%d;%p2%ds"
    call writefile([ "\e[?6;69h" ], "/dev/tty", "a")
  endfunction

  " old vim does not ignore CPR
  map <special> <Esc>[3;9R <Nop>

  " new vim can't handle CPR with direct mapping
  " map <expr> ^[[3;3R EnableVsplitMode()
  set t_F9=^[[3;3R
  map <expr> <t_F9> EnableVsplitMode()
  let &t_RV .= "\e[?6;69h\e[1;3s\e[3;9H\e[6n\e[0;0s\e[?6;69l"
endif

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" settings for plugins
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
if &compatible
  set nocompatible
endif

source ~/dotfiles/vim/dein.vim
source ~/dotfiles/vim/keymap.vim

" colorscheme
if (empty($TMUX))
  if (has("nvim"))
    let $NVIM_TUI_ENABLE_TRUE_COLOR=1
  endif
  if (has("termguicolors"))
    set termguicolors
  endif
endif
syntax on
colorscheme onedark
