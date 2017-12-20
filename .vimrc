" create esc key
inoremap jk <esc>

"" NeoBundle core
if has('vim_starting')
  set nocompatible               " Be iMproved

  " Required:
  set runtimepath+=~/.vim/bundle/neobundle.vim/
endif

let neobundle_readme=expand('~/.vim/bundle/neobundle.vim/README.md')
" let solarized_vim=expand('~/.vim/colors/solarized.vim')

let g:vim_bootstrap_langs = "javascript,ruby,python,html,go"
let g:vim_bootstrap_editor = "vim"				" nvim or vim

" neobundle settings
if !filereadable(neobundle_readme)
  echo "Installing NeoBundle..."
  echo ""
  silent !mkdir -p ~/.vim/bundle
  silent !git clone https://github.com/Shougo/neobundle.vim ~/.vim/bundle/neobundle.vim/
  let g:not_finsh_neobundle = "yes"

  " Run shell script if exist on custom select language
endif

" Required:
call neobundle#begin(expand('~/.vim/bundle/'))

" Let NeoBundle manage NeoBundle
" Required:
NeoBundleFetch 'Shougo/neobundle.vim'

"*****************************************************************************
"" Functions
"*****************************************************************************

function! s:meet_neocomplete_requirements()
  return has('lua') && (v:version > 703 || (v:version == 703 && has('patch885')))
endfunction

"*****************************************************************************
"" VimProc DLL Path
"*****************************************************************************
"if has('mac')
"  let g:vimproc_dll_path = $VIMRUNTIME . '/autoload/vimproc_mac.so'
"elseif has('win32')
"  let g:vimproc_dll_path = $HOME . '.vim/bundle/vimproc/autoload/vimproc_win32.dll'
"elseif has('win64')
"  let g:vimproc_dll_path = $HOME . '.vim/bundle/vimproc/autoload/vimproc_win64.dll'
"endif


"*****************************************************************************
"" NeoBundle install packages
"*****************************************************************************
" NeoBundle 'altercation/vim-colors-solarized'
NeoBundle 'scrooloose/nerdtree'

" statusline
NeoBundle 'Lokaltog/powerline', {'rtp': 'powerline/bindings/vim/'}


"" vimproc
NeoBundle 'Shougo/vimproc', {
  \ 'build' : {
    \ 'windows' : 'make -f make_mingw32.mak',
    \ 'cygwin' : 'make -f make_cygwin.mak',
    \ 'mac' : 'make -f make_mac.mak',
    \ 'unix' : 'make -f make_unix.mak',
  \ },
\ }

"" 補完
if s:meet_neocomplete_requirements()
  NeoBundle 'Shougo/neocomplete'
	"" NeoBundle 'supermomonga/neocomplete-rsense.vim', {'depends': ['Shougo/neocomplete.vim', 'marcus/rsense'],}
else
	NeoBundle 'Shougo/neocomplcache'
	"" NeoBundle 'Shougo/neocomplcache-rsense.vim', {'depends': ['Shougo/neocomplcache.vim', 'marcus/rsense'],}
endif

"" スニペット
NeoBundle 'Shougo/neosnippet'
NeoBundle 'Shougo/neosnippet-snippets'
NeoBundle 'honza/vim-snippets'

"" ctags
NeoBundle 'majutsushi/tagbar'
NeoBundle 'szw/vim-tags'

NeoBundle 'tpope/vim-endwise'

"" 構文チェック
NeoBundle 'scrooloose/syntastic'
NeoBundle 'pmsorhaindo/syntastic-local-eslint.vim'

"" markdownプレビュー
NeoBundle 'plasticboy/vim-markdown'
NeoBundle 'kannokanno/previm'
NeoBundle 'tyru/open-browser.vim'

"" python構文・コーディング規約チェック
NeoBundle 'Flake8-vim'
NeoBundle 'davidhalter/jedi-vim'
NeoBundle 'hynek/vim-python-pep8-indent'

"" indent可視化
NeoBundle 'Yggdroot/indentLine'

"" HTML/CSS
" NeoBundle 'amirh/HTML-AutoCloseTag'
NeoBundle 'hail2u/vim-css3-syntax'
NeoBundle 'gorodinskiy/vim-coloresque'
NeoBundle 'mattn/emmet-vim'

NeoBundle 'tpope/vim-surround'

NeoBundle 'othree/yajs.vim'

"" JSON syntax
NeoBundle 'elzr/vim-json'

NeoBundle 'leafgarland/typescript-vim'
NeoBundle 'jason0x43/vim-js-indent'

"" mustache / handlebars
NeoBundle 'mustache/vim-mustache-handlebars'

"" nodejs補完
NeoBundle 'myhere/vim-nodejs-complete'

"" VCL
NeoBundle 'smerrill/vcl-vim-plugin'

"" complete for braces
NeoBundle 'cohama/lexima.vim'

"" ctrlp
NeoBundle 'ctrlpvim/ctrlp.vim'

"" ag for ctrlp
NeoBundle 'rking/ag.vim'

let g:ctrlp_use_migemo = 1
let g:ctrlp_clear_cache_on_exit = 0
let g:ctrlp_mruf_max = 500
let g:ctrlp_open_new_file = 1
if executable('ag') " agが使える環境の場合
  let g:ctrlp_use_caching=0 " CtrlPのキャッシュを使わない
  let g:ctrlp_user_command='ag %s -i --nocolor --nogroup -g ""' " 「ag」の検索設定
endif

call neobundle#end()

" Required:
filetype plugin indent on

" If there are uninstalled bundles found on startup,
" this will conveniently prompt you to install them.
NeoBundleCheck



"*******************************************************************************
"" dein plugin
"*******************************************************************************
"
" Required
"set runtimepath+=/Users/kenichi/.vim/dein/repos/github.com/Shougo/dein.vim

" Required
"
" if dein#load_state('/Users/kenichi/.vim/dein')
"  call dein#begin('/Users/kenichi/.vim/dein')
"
"  " Let dein manage dein
"  " Required
"  call dein#add('/Users/kenichi/.vim/dein/repos/github.com/Shougo/dein.vim')
"
"  " Add or remove your plugins here
"  call dein#add('Shougo/vimproc.vim', {'build': 'make'})
"  call dein#add('Shougo/neocomplete.vim')
"  call dein#add('Shougo/neosnippet')
"  call dein#add('Shougo/neosnippet-snippets')
"  call dein#add('itchyny/lightline.vim')
"  call dein#add('bronson/vim-trailing-whitespace')
"  call dein#add('Yggdroot/indentLine')
"  call dein#add('ctrlpvim/ctrlp.vim')
"  call dein#add('tacahiroy/ctrlp-funky')
"  call dein#add('suy/vim-ctrlp-commandline')
"  call dein#add('pmsorhaindo/syntastic-local-eslint.vim')
"
"  " You can specify revision/branch/tag.
"  call dein#add('Shougo/vimshell', { 'rev': '3787e5' })
"
"  " Required
"  call dein#end()
"  call dein#save_state()
"endif

" If you want to install not installed plugins on startup.
"if dein#check_install()
"  call dein#install()
"endif


"*******************************************************************************
" Basic Setup
"*******************************************************************************

let mapleader="\<Space>"

set encoding=utf-8
set fileencoding=utf-8 " 保存時の文字コード
set fileencodings=ucs-boms,utf-8,euc-jp,cp932 " 読み込み時の文字コードの自動判別. 左側が優先される
set fileformats=unix,dos,mac " 改行コードの自動判別. 左側が優先される
set ambiwidth=double " □や○文字が崩れる問題を解決
" encoding
set bomb
set binary
set ttyfast

set autoread " 編集中のファイルが変更されたら自動で読み直す
set hidden " バッファが編集中でもその他のファイルを開けるように
set showcmd " 入力中のコマンドをステータスに表示する

" tab, indent
set expandtab " タブ入力を複数の空白入力に置き換える
set tabstop=4 " 画面上でタブ文字が占める幅
set softtabstop=4 " 連続した空白に対してタブキーやバックスペースキーでカーソルが動く幅
set autoindent " 改行時に前の行のインデントを継続する
set smartindent " 改行時に前の行の構文をチェックし次の行のインデントを増減する
set shiftwidth=4 " smartindentで増減する幅

" Search
set hlsearch
set incsearch " インクリメンタルサーチ. １文字入力毎に検索を行う
set ignorecase " 検索パターンに大文字小文字を区別しない
set smartcase " 検索パターンに大文字を含んでいたら大文字小文字を区別する
set hlsearch " 検索結果をハイライト
set wrapscan " 検索時に最後まで行ったら最初に戻る

set number " 行番号を表示
" set cursorline " カーソルラインをハイライト
set nocursorline " カーソルラインをハイライトしない
" set cursorcolumn " 現在の行を強調表示（縦）
set nocursorcolumn " 現在の行をハイライトしない
set norelativenumber " 行番号の相対表示しない
set virtualedit=onemore " 行末の1文字先までカーソルを移動できるように
set smartindent " インデントはスマートインデント
set visualbell " ビープ音を可視化
set laststatus=2 " ステータスラインを常に表示
set wildmode=list:longest " コマンドラインの補完

set fileformats=unix,dos,mac
set showcmd
set shell=/bin/zsh

set nobackup
set noswapfile

" key setting
nnoremap j gj
nnoremap k gk
nnoremap <down> gj
nnoremap <up> gk
set whichwrap=h,l,b,s,<,>,[,]

" バックスペースキーの有効化
set backspace=indent,eol,start

set showmatch " 括弧の対応関係を一瞬表示する
source $VIMRUNTIME/macros/matchit.vim " Vimの「%」を拡張する

set wildmenu " コマンドモードの補完
set history=1000 " 保存するコマンド履歴の数

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

" paste
"if &term =~ "xterm"
"    let &t_SI .= "\e[?2004h"
"    let &t_EI .= "\e[?2004l"
"    let &pastetoggle = "\e[201~"
"
"    function XTermPasteBegin(ret)
"        set paste
"        return a:ret
"    endfunction
"
"    inoremap <special> <expr> <Esc>[200~ XTermPasteBegin("")
"endif

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

"*****************************************************************************
"" Visual Settings
"*****************************************************************************
syntax enable
set background=dark
" colorscheme molokai
colorscheme onedark
set number
set ruler

"*****************************************************************************
" syntax highlight
"*****************************************************************************
syntax on

"*****************************************************************************
" split settings
"*****************************************************************************
nnoremap s <Nop>
nnoremap :ss :split
nnoremap :vs :vsplit
nnoremap sj <C-w>j
nnoremap sk <C-w>k
nnoremap sl <C-w>l
nnoremap sh <C-w>h
nnoremap sJ <C-w>J
nnoremap sK <C-w>K
nnoremap sL <C-w>L
nnoremap sH <C-w>H
nnoremap sn gt
nnoremap sp gT
nnoremap sr <C-w>r
nnoremap s= <C-w>=
nnoremap sw <C-w>w
nnoremap so <C-w>_<C-w>|
nnoremap sO <C-w>=
nnoremap sN :<C-u>bn<CR>
nnoremap sP :<C-u>bp<CR>
nnoremap st :<C-u>tabnew<CR>
nnoremap sT :<C-u>Unite tab<CR>
nnoremap ss :<C-u>sp<CR>
nnoremap sv :<C-u>vs<CR>
nnoremap sq :<C-u>q<CR>
nnoremap sQ :<C-u>bd<CR>
nnoremap sJ <C-w>J
nnoremap sK <C-w>K
nnoremap sL <C-w>L
nnoremap sH <C-w>H
nnoremap sn gt
nnoremap sp gT
nnoremap sr <C-w>r
nnoremap s= <C-w>=
nnoremap sw <C-w>w
nnoremap so <C-w>_<C-w>|
nnoremap sO <C-w>=
nnoremap sN :<C-u>bn<CR>
nnoremap sP :<C-u>bp<CR>
nnoremap ss :<C-u>sp<CR>
nnoremap sv :<C-u>vs<CR>
nnoremap sq :<C-u>q<CR>
nnoremap sQ :<C-u>bd<CR>

"*****************************************************************************
"" Abbreviations
"*****************************************************************************
"" NERDTree
let g:NERDTreeChDirMode=2
let g:NERDTreeIgnore=['\.rbc$', '\~$', '\.pyc$', '\.db$', '\.sqlite$', '__pycache__', 'node_modules', 'bower_components']
let g:NERDTreeSortOrder=['^__\.py$', '\/$', '*', '\.swp$', '\.bak$', '\~$']
let g:NERDTreeShowBookmarks=1
let g:nerdtree_tabs_focus_on_files=1
let g:NERDTreeMapOpenInTabSilent = '<RightMouse>'
let g:NERDTreeWinSize = 20
set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.db,*.sqlite
nnoremap <silent> <leader>nf :NERDTreeFind<CR>
noremap <leader>n :NERDTreeToggle<CR>

"*****************************************************************************
""" Mappings
"*****************************************************************************
"" Copy/Paste/Cut
set clipboard=unnamed,unnamedplus

"******************
"" neosnippet
imap <c-k>     <Plug>(neosnippet_expand_or_jump)
smap <c-k>     <Plug>(neosnippet_expand_or_jump)
xmap <c-k>     <Plug>(neosnippet_expand_target)
imap <expr><TAB> neosnippet#expandable_or_jumpable() ? "\<Plug>(neosnippet_expand_or_jump)": pumvisible() ? "\<C-n>" : "\<TAB>"
smap <expr><TAB> neosnippet#expandable_or_jumpable() ? "\<Plug>(neosnippet_expand_or_jump)": "\<TAB>"
if has('conceal')
	set conceallevel=2 concealcursor=i
endif
"******************

"******************
if s:meet_neocomplete_requirements()
  "" neocomplete
  let g:neocomplete#enable_at_startup = 1
  let g:neocomplete#enable_ignore_case = 1
  let g:neocomplete#enable_smart_case = 1
  if !exists('g:neocomplete#keyword_patterns')
	let g:neocomplete#keyword_patterns = {}
  endif
  let g:neocomplete#keyword_patterns._ = '\h\w*'
else
  "" neocomplcache
  let g:neocomplcache_enable_at_startup = 1
  let g:neocomplcache_enable_ignore_case = 1
  let g:neocomplcache_enable_smart_case = 1
  if !exists('g:neocomplcache_keyword_patterns')
	let g:neocomplcache_keyword_patterns = {}
  endif
  let g:neocomplcache_keyword_patterns._ = '\h\w*'
  let g:neocomplcache_enable_camel_case_completion = 1
  let g:neocomplcache_enable_underbar_completion = 1
endif

" <TAB>: completion.                                         
inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"   
inoremap <expr><S-TAB>  pumvisible() ? "\<C-p>" : "\<S-TAB>" 
"******************

"******************
" tagbar
if ! empty(neobundle#get("tagbar"))
  let g:tagbar_width = 20
  nn <silent> <leader>t :TagbarToggle<CR>
endif
"******************

"******************
" ctags
let g:vim_tags_project_tags_command = "/usr/local/Cellar/ctags/5.8_1/bin/ctags -f .tags -R . 2>/dev/null"
let g:vim_tags_gems_tags_command = "/usr/local/Cellar/ctags/5.8_1/bin/ctags -R -f .Gemfile.lock.tags `bundle show --paths` 2>/dev/null"
let g:vim_tags_auto_generate = 1
set tags+=.tags
set tags+=.Gemfile.lock.tags

if has("path_extra")
  set tags+=tags;
endif

nnoremap <C-]> g<C-]> 
"******************

"******************
" syntastic
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_mode_map = { 'mode': 'passive', 'active_filetypes': ['ruby', 'javasctipt'] }
let g:syntastic_ruby_checkers=['rubocop']
let g:syntastic_python_checkers = ['pyflakes', 'pep8']
let g:syntastic_javascript_checkers=['eslint']
let g:syntastic_coffee_checkers = ['coffeelint']
let g:syntastic_scss_checkers = ['scss_lint']

let g:syntastic_enable_signs = 1
let g:syntastic_always_populate_loc_list = 0
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0

" check syntax errors
let g:syntastic_enable_signs = 1
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 1


"******************

"******************
" typescript
au BufRead,BufNewFile,BufReadPre *.ts set filetype=typescript
autocmd FileType typescript setlocal sw=2 sts=2 ts=2 et
"******************

"******************
let g:user_emmet_leader_key='<c-e>'
let g:user_emmet_settings = {
			\    'variables': {
			\      'lang': "ja"
			\    },
			\   'indentation': '  '
			\ }
"******************

"******************
" rsense
if !exists('g:neocomplete#force_omni_input_patterns')
	let g:neocomplete#force_omni_input_patterns = {}
endif
let g:neocomplete#force_omni_input_patterns.ruby = '[^. *\t]\.\w*\|\h\w*::'
let g:neocomplete#sources#rsense#home_directory = '/usr/local/bin/rsense'
"******************

"******************
" PyFlake
let g:PyFlakeOnWrite = 1
let g:PyFlakeCheckers = 'pep8,mccabe,pyflakes'
let g:PyFlakeDefaultComplexity=10
"******************

"******************
" jedi
autocmd FileType python setlocal omnifunc=jedi#completions
let g:jedi#completions_enabled = 0
let g:jedi#auto_vim_configuration = 0

if !exists('g:neocomplete#force_omni_input_patterns')
	let g:neocomplete#force_omni_input_patterns = {}
endif

let g:neocomplete#force_omni_input_patterns.python = '\h\w*\|[^. \t]\.\w*'
"******************

"******************
" typescript
autocmd BufRead,BufNewFile *.ts set filetype=typescript
let g:typescript_indent_disable = 1
"******************

"******************
" indentLine
let g:indentLine_fileTypeExclude = ['help', 'nerdtree', 'calendar', 'thumbnail']
"******************

"******************
" mustache / handlebars
let g:mustache_abbreviations = 1
"******************

"******************
" vim-nodejs-complete
:setl omnifunc=jscomplete#CompleteJS
if !exists('g:neocomplcache_omni_functions')
  let g:neocomplcache_omni_functions = {}
endif
let g:neocomplcache_omni_functions.javascript = 'nodejscomplete#CompleteJS'
"******************

"*****************************************************************************
" Indent Width
"*****************************************************************************
set shiftwidth=2
set tabstop=2

augroup indent
  autocmd! FileType python setlocal shiftwidth=4 tabstop=4
augroup END

set autoindent
set expandtab


"*****************************************************************************
" Large File
"*****************************************************************************"
set synmaxcol=256
set wrap

" file is large from 10mb
let g:LargeFile = 1024 * 100
augroup LargeFile
  autocmd BufReadPre * let f=getfsize(expand("<afile>")) | if f > g:LargeFile || f == -2 | call LargeFile() | endif
augroup END

function LargeFile()
  " no syntax highlighting etc
  set eventignore+=FileType
  " save memory when other file is viewed
  setlocal bufhidden=unload
  " display message
  autocmd VimEnter *  echo "The file is larger than " . (g:LargeFile / 1024 / 1024) . " MB, so some options are changed (see .vimrc for details)."
endfunction

