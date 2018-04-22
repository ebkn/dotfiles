""*******************************************************************************
" Basic Setup
"*******************************************************************************

set shell=/bin/zsh

" encoding
set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8,ucs-boms,euc-jp,ep932
set fileformats=unix,dos,mac
set ambiwidth=double " □や○文字が崩れる問題を解決
set nobomb "bomb無効化

" Leaderをspaceキーに設定する
let mapleader="\<Space>"

set ttyfast " 高速ターミナル接続
set autoread " 編集中のファイルが変更されたら自動で読み直す
set hidden " バッファが編集中でもその他のファイルを開けるように
set showcmd " 入力中のコマンドをステータスに表示する

" ファイル作成
set nobackup " backupを作成しない
set noswapfile " swapfileを作成しない
set nowritebackup " 上書き成功時にbackup破棄
set noundofile " undofileを作成しない

" %jump
set showmatch " 括弧の対応関係を一瞬表示する
source $VIMRUNTIME/macros/matchit.vim " vimの%を拡張

" completion
set wildmenu wildmode=list:full " コマンドモードの補完
set history=1000 " 保存するコマンド履歴の数

set visualbell " ビープ音を可視化
set laststatus=2 " ステータスラインを常に表示
set wildmode=list:longest " コマンドラインの補完

" tab, indent
set expandtab " タブ入力を複数の空白入力に置き換える
set tabstop=2 " 画面上でタブ文字が占める幅
set softtabstop=2 " 連続した空白に対してタブキーやバックスペースキーでカーソルが動く幅
set autoindent " 改行時に前の行のインデントを継続する
set smartindent " 改行時に前の行の構文をチェックし次の行のインデントを増減する
set shiftwidth=2 " smartindentで増減する幅

" Search
set incsearch " インクリメンタルサーチ
set ignorecase " 検索パターンに大文字小文字を区別しない
set smartcase " 検索パターンに大文字を含んでいたら大文字小文字を区別する
set hlsearch " 検索結果をハイライト
set wrapscan " 検索時に最後まで行ったら最初に戻る

" cursor
set whichwrap=b,s,h,l,<,>,[,],~ " 左右移動で前後の行に移動
set virtualedit=onemore " 行末の1文字先までカーソルを移動できるように
set number " 行番号
set nocursorline " カーソルラインをハイライトしない
set nocursorcolumn " 現在の行をハイライトしない
set norelativenumber " 行番号の相対表示しない
set backspace=indent,eol,start " バックスペースキー有効化
set ruler
" 折り返し表示の際に表示行単位でカーソル移動
nnoremap j gj
nnoremap k gk
nnoremap <down> gj
nnoremap <up> gk

" マウス有効化
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

" 全角スペースの表示
function! ZenkakuSpace()
    highlight ZenkakuSpace cterm=underline ctermfg=lightblue guibg=darkgray
endfunction
if has('syntax')
    augroup ZenkakuSpace
        autocmd!
        autocmd ColorScheme * call ZenkakuSpace()
        autocmd VimEnter,WinEnter,BufRead * let w:m1=matchadd('ZenkakuSpace', '　')
    augroup END
    call ZenkakuSpace()
endif

" ペースト設定
if &term =~ "xterm"
  let &t_SI .= "\e[let &t_SI .= "\e[?2004h"
  let &t_EI .= "\e[?2004l"
  let &pastetoggle = "\e[201~"

  function XTermPasteBegin(ret)
    set paste
    return a:ret
  endfunction

  inoremap <special> <expr> <Esc>[200~ XTermPasteBegin("")
endif


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" dein
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
if &compatible
  set nocompatible
endif
set runtimepath+=~/.cache/dein/repos/github.com/Shougo/dein.vim

if dein#load_state('~/.cache/dein')
  call dein#begin('~/.cache/dein')
  call dein#add('~/.cache/dein')

  " color
  call dein#add('sheerun/vim-polyglot')
  
  " サイドバーにtree表示
  call dein#add('scrooloose/nerdtree')
  call dein#add('ryanoasis/vim-devicons')
  call dein#add('tiagofumo/vim-nerdtree-syntax-highlight')

  call dein#add('Shougo/vimproc', {
    \ 'build' : {
      \ 'windows' : 'make -f make_mingw32.mak',
      \ 'cygwin' : 'make -f make_cygwin.mak',
      \ 'mac' : 'make -f make_mac.mak',
      \  'unix' : 'make -f make_unix.mak',
    \ },
  \ }) " 重たい処理を非同期にして高速化

  " スニペット
  call dein#add('Shougo/neocomplcache')
  call dein#add('Shougo/neosnippet')
  call dein#add('Shougo/neosnippet-snippets')

  " 一括コメントアウト
  call dein#add('tyru/caw.vim.git')

  call dein#end()
  call dein#save_state()
endif

if dein#check_install()
  call dein#install()
end

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" ライブラリの設定

filetype plugin indent on

" colorscheme
if (empty($TMUX))
  if (has("nvim"))
    let $NVIM_TUI_ENABLE_TRUE_COLOR=1
  endif
  if (has("termguicolors"))
    set termguicolors
  endif
endif " tmuxがロードされていない時の設定
syntax on " syntax有効化
colorscheme onedark
" molokai用設定
" colorscheme molokai
" let g:molokai_original=1
" let g:rehash256=1
set t_Co=256 " 256色を指定
set background=dark " 背景色

" NERDTree
" 自動起動設定
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
map <silent><C-n> :NERDTreeToggle<CR>
let NERDTreeShowHidden=1 " dotfile表示

" スニペットの初期設定
imap <C-k> <Plug>(neosnippet_expand_or_jump)
smap <C-k> <Plug>(neosnippet_expand_or_jump)
xmap <C-k> <Plug>(neosnippet_expand_target)
smap <expr><TAB> neosnippet#expandable_or_jumpable() ?
\ "\<Plug>(neosnippet_expand_or_jump)" : "\<TAB>"
if has('conceal')
  set conceallevel=2 concealcursor=niv
endif

" caw.vim.gitで一括コメントアウト
nmap <C-/> <Plug>(caw:hatpos:toggle)
vmap <C-/> <Plug>(caw:hatpos:toggle)

