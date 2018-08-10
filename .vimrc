set shell=/bin/zsh

" encoding
set encoding=utf8
scriptencoding utf8
set fileencoding=utf-8
set termencoding=utf8
set fileencodings=utf-8,ucs-boms,euc-jp,ep932
set fileformats=unix,dos,mac
set ambiwidth=double " □や○文字が崩れる問題を解決
set nobomb "bomb無効化
set t_Co=256 " 256色を指定

set ttyfast " 高速ターミナル接続
set lazyredraw " 再描画を調節
set autoread " 編集中のファイルが変更されたら自動で読み直す
set hidden " バッファが編集中でもその他のファイルを開けるように
set showcmd " 入力中のコマンドをステータスに表示する
set noshowmode " モード表示しない

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
set wildignore+=*/tmp*,*.so,*.swp,*.zip " 検索等に含めないファイル

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

" clipboard
set clipboard=unnamed,autoselect

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
  let &t_SI .= "\e[?2004h"
  let &t_EI .= "\e[?2004l"
  let &pastetoggle = "\e[201~"

  function XTermPasteBegin(ret)
    set paste
    return a:ret
  endfunction

  inoremap <special> <expr> <Esc>[200~ XTermPasteBegin("")
endif

" 画面分割
nnoremap s <Nop>
nnoremap sj <C-w>j
nnoremap sk <C-w>k
nnoremap sl <C-w>l
nnoremap sh <C-w>h
nnoremap sJ <C-w>J
nnoremap sK <C-w>K
nnoremap sL <C-w>L
nnoremap sH <C-w>H
nnoremap ss :<C-u>sp<CR>
nnoremap sv :<C-u>vs<CR>
nnoremap sq :<C-u>q<CR>

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vim packages
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
if &compatible
  set nocompatible
endif
set runtimepath+=~/.cache/dein/repos/github.com/Shougo/dein.vim

if dein#load_state('~/.cache/dein')
  call dein#begin('~/.cache/dein')
  call dein#add('~/.cache/dein')

  " autosave
  call dein#add('vim-scripts/vim-auto-save')

  " color
  call dein#add('sheerun/vim-polyglot')

  " ステータスバー
  call dein#add('itchyny/lightline.vim')
  call dein#add('tpope/vim-fugitive')

  " サイドバーにtree表示
  call dein#add('scrooloose/nerdtree')
  " call dein#add('ryanoasis/vim-devicons') " 現状文字が残ってうまく表示できない
  call dein#add('tiagofumo/vim-nerdtree-syntax-highlight')
  call dein#add('Xuyuanp/nerdtree-git-plugin')

  " 差分の行を表示する
  call dein#add('airblade/vim-gitgutter')

  " 重たい処理を非同期にして高速化
  call dein#add('Shougo/vimproc', {
    \ 'build' : {
      \ 'windows' : 'make -f make_mingw32.mak',
      \ 'cygwin' : 'make -f make_cygwin.mak',
      \ 'mac' : 'make -f make_mac.mak',
      \ 'unix' : 'make -f make_unix.mak',
    \ },
  \ })

  " 補完
  call dein#add('Shougo/neocomplete')
  call dein#add('Shougo/neosnippet.vim')
  call dein#add('Shougo/neosnippet-snippets')

  " fzf
  call dein#add('/usr/local/opt/fzf')
  call dein#add('junegunn/fzf.vim')

  " git grep
  call dein#add('mhinz/vim-grepper')

  " 一括コメントアウト
  call dein#add('tyru/caw.vim.git')

  " 空白文字ハイライト
  call dein#add('bronson/vim-trailing-whitespace')

  " 置き換えをハイライト
  call dein#add('osyo-manga/vim-over')

  " 構文チェック
  call dein#add('w0rp/ale')

  " golang
  call dein#add('fatih/vim-go')

  " prettier
  call dein#add('prettier/vim-prettier', { 'do': 'yarn install' })

  " jsx
  call dein#add('pangloss/vim-javascript')
  call dein#add('mxw/vim-jsx')

  " typescript
  call dein#add('leafgarland/typescript-vim')
  call dein#add('ianks/vim-tsx')

  " ansible
  call dein#add('pearofducks/ansible-vim')

  " emmet
  call dein#add('mattn/emmet-vim')

  " htmlのタグを自動で閉じる
  call dein#add('alvan/vim-closetag')

  " rubyでend自動挿入
  call dein#add('tpope/vim-endwise')
  " rubyコード補完
  call dein#add('marcus/rsense')

  " processing
  call dein#add('sophacles/vim-processing')

  " markdown
  call dein#add('plasticboy/vim-markdown')

  " color表示
  call dein#add('gorodinskiy/vim-coloresque')

  call dein#end()
  call dein#save_state()
endif

if dein#check_install()
  call dein#install()
end

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" settings for packages
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""

filetype plugin indent on " ファイルごとのindent

" autosave
let g:autosave=1

" colorscheme
if (empty($TMUX))
  if (has("nvim"))
    let $NVIM_TUI_ENABLE_TRUE_COLOR=1
  endif
  if (has("termguicolors"))
    set termguicolors
  endif
endif

syntax on " syntax有効化
colorscheme onedark
" molokai用設定
" colorscheme molokai
" let g:molokai_original=1
" let g:rehash256=1
set background=dark " 背景色

" lightline
let g:lightline = {
  \ 'colorscheme': 'onedark',
  \ 'active': {
  \   'left': [
  \     [ 'mode', 'paste' ],
  \     [ 'gitbranch', 'readonly', 'relativepath', 'modified' ]
  \   ],
  \   'right': [
  \     [ 'percent' ],
  \     [ 'fileencoding', 'filetype']
  \   ]
  \ },
  \ 'inactive': {
  \   'left': [
  \     [ 'gitbranch', 'readonly', 'relativepath', 'modified' ]
  \   ],
  \   'right': []
  \ },
  \ 'component_function': {
  \   'gitbranch': 'fugitive#head'
  \ },
\ }

" NERDTree
" 自動起動設定
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
map <silent><C-n> :NERDTreeToggle<CR>
let NERDTreeShowHidden=1 " dotfile表示
let NERDTreeIgnore=['\.DS_Store', '\.git$', 'node_modules', 'bower_components', '__pycache__', '\.db', '\.sqlite$', '\.rbc$', '\~$', '\.pyc', '\.idea$', '\.vscode$', '\vendor\/bundle', '\.awcache$']
let g:NERDTreeDirArrows=1 " ディレクトリツリーの矢印指定
let g:NERDTreeDirArrowExpandable='▸'
let g:NERDTreeDirArrowCollapsible='▾'
" どのファイルをsyntaxhighlightするか設定
let g:NERDTreeFileExtensionHighlightFullName=1
let g:NERDTreeExactMatchHighlightFullName=1
let g:NERDTreePatternMatchHighlightFullName=1
let g:NERDTreeLimitedSyntax=1 " 遅延解消
set guifont=SauseCodePro\ Nerd\ Font\ Medium:h14
" syntax highlight
let s:brown = "905532"
let s:aqua =  "3AFFDB"
let s:blue = "689FB6"
let s:darkBlue = "44788E"
let s:purple = "834F79"
let s:lightPurple = "834F79"
let s:red = "AE403F"
let s:beige = "F5C06F"
let s:yellow = "F09F17"
let s:orange = "D4843E"
let s:darkOrange = "F16529"
let s:pink = "CB6F6F"
let s:salmon = "EE6E73"
let s:green = "8FAA54"
let s:lightGreen = "31B53E"
let s:white = "FFFFFF"
let s:rspec_red = 'FE405F'
let s:git_orange = 'F54D27'
let g:NERDTreeExtensionHighlightColor = {}
let g:NERDTreeExactMatchHighlightColor = {}
let g:NERDTreePatternMatchHighlightColor = {}
" git plugin
let g:NERDTreeIndicatorMapCustom = {
    \ "Modified"  : "✹",
    \ "Staged"    : "✚",
    \ "Untracked" : "✭",
    \ "Renamed"   : "➜",
    \ "Unmerged"  : "═",
    \ "Deleted"   : "✖",
    \ "Dirty"     : "✗",
    \ "Clean"     : "✔︎",
    \ 'Ignored'   : '☒',
    \ "Unknown"   : "?"
    \ }

" 補完
let g:acp_enableAtStartup=1 " 起動時に有効にするために設定
let g:neocomplete#enable_at_startup=1 " vim起動時に有効にする
let g:neocomplete#enable_smart_case=1 " 大文字が入力されるまで大文字小文字区別しない
let g:neocomplete#sources#syntax#min_keyword_length=2 " 2文字以上の単語に対して保管する
let g:neocomplete#enable_underbar_completion=1 " アンダーバー有効化
let g:neocomplete#enable_camel_case_completion=1 " キャメルケース有効化
let g:neocomplete#enable_auto_delimiter=1 " 区切り文字を含める
let g:neocomplete#auto_completion_start_length=2 " 2文字目から開始
let g:neocomplete#max_list=15 " 表示数
" dictionary設定
let g:neocomplete#sources#dictionary#dictionaries={
  \ 'default': '',
  \ 'vimshell': $HOME.'/.vimshell_hist',
  \ 'scheme': $HOME.'/.gosh_completions'
\ }
" keyword設定
if !exists('g:neocomplete#keyword_patterns')
  let g:neocomplete#keyword_patterns={}
endif
let g:neocomplete#keyword_patterns['default']='\h\w*'
" keymap
" <CR>: close popup and save indent.
inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
function! s:my_cr_function()
  return (pumvisible() ? "\<C-y>" : "" ) . "\<CR>"
endfunction
" <TAB>: completion.
inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
" Close popup by <Space>.
" inoremap <expr><Space> pumvisible() ? "\<C-y>" : "\<Space>"

" neosnippet呼び出し
imap <C-k> <Plug>(neosnippet_expand_or_jump)
smap <C-k> <Plug>(neosnippet_expand_or_jump)
xmap <C-k> <Plug>(neosnippet_expand_target)
smap <expr><TAB> neosnippet#expandable_or_jumpable() ? "\<Plug>(neosnippet_expand_or_jump)" : "\<TAB>"
" タブキーで補完候補の選択. スニペット内のジャンプもタブキーでジャンプ
imap <expr><TAB> pumvisible() ? "<C-n>" : neosnippet#jumpable() ? "<Plug>(neosnippet_expand_or_jump)" : "<TAB>"
if has('conceal')
  set conceallevel=2 concealcursor=niv
endif
let g:neosnippet#snippets_directory='~/.vim/bundle/neosnippet-snippets/snippets/' " 補完のディレクトリ指定

" fzf設定
map <C-t> :Files<CR>
let g:fzf_layout = { 'down': '~40%' }
let g:fzf_buffers_jump=1

" grepper設定
map <C-g> :Grepper -tool ag -highlight<CR>

" ale設定
let g:ale_lint_on_text_changed=0
let g:ale_sign_column_always=1 " 左にずれるのを防止
let g:ale_sign_error='E'
let g:ale_sign_warning='W'
let g:ale_linters = {
  \ 'html': [],
  \ 'css': ['stylelint'],
  \ 'javascript': ['eslint'],
  \ 'ruby': ['rubocop'],
  \ 'go': ['golint'],
  \ 'haml': ['haml-lint'],
  \ 'sass': ['sass-lint'],
  \ 'swift': ['swiftlint'],
  \ 'typescript': ['tslint'],
  \ 'vim': ['vint'],
  \ 'yaml': ['yamllint'],
  \ }

" gitgutter設定
let g:gitgutter_async=1

" caw.vim設定
nmap <C-c> <Plug>(caw:i:toggle)
vmap <C-c> <Plug>(caw:i:toggle)

" html autoclose設定
let g:closetag_filenames='*.html,*.xhtml,*.phtml'
let g:closetag_xhtml_filenames='*.xhtml,*.jsx,*.tsx'
let g:closetag_emptyTags_caseSensitive=1
let g:closetag_shortcut='>' " >を押すと自動で閉じる
let g:closetag_close_shortcat='<leader>>'

" emmet
let g:user_emmet_leader_key='<C-e>'

" vim-processing設定
let g:processing_fold=1

" vim-markdown設定
let g:vim_markdown_folding_disabled=1
