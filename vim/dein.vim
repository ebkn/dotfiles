" cache dir
let s:cache_home=expand('~/.cache')
let s:dein_dir=s:cache_home . '/dein'

" install dein if missing
let s:dein_repo_dir=s:dein_dir . '/repos/github.com/Shougo/dein.vim'
if !isdirectory(s:dein_repo_dir)
  call systam('git clone git@github.com:Shougo/dein.vim.git ' . shellescape(s:dein_repo_dir))
endif
let &runtimepath=s:dein_repo_dir . "," . &runtimepath

" settings file
let s:toml_dir=expand('~/dotfiles/vim/dein/')
let s:toml=s:toml_dir . 'dein.toml'
let s:toml_lazy=s:toml_dir . 'dein-lazy.toml'

" load plugins
if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)

  call dein#load_toml(s:toml)
  call dein#load_toml(s:toml_lazy, {'lazy': 1})

  call dein#end()
  call dein#save_state()
endif

" install missing plugins
if dein#check_install()
  call dein#install()
endif