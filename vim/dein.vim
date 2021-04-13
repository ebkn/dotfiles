" cache dir
let s:cache_home=expand('~/.cache')
let s:dein_dir=s:cache_home . '/dein'

" install dein if missing
let s:dein_repo_dir=s:dein_dir . '/repos/github.com/Shougo/dein.vim'
if !isdirectory(s:dein_repo_dir)
  call system('git clone git@github.com:Shougo/dein.vim.git ' . shellescape(s:dein_repo_dir))
endif
let &runtimepath=s:dein_repo_dir . "," . &runtimepath

" settings file location
let s:toml_dir=expand('~/dotfiles/vim/dein/')

" load plugins
if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)

  " load plugins instantly
  let s:instantlyFiles=glob(s:toml_dir . 'instantly/*.toml')
  for s:file in split(s:instantlyFiles, "\n")
    call dein#load_toml(s:file)
  endfor

  " nvim
  if !has('nvim')
    call dein#add('roxma/nvim-yarp')
    call dein#add('roxma/vim-hug-neovim-rpc')
  endif

  " load plugins lazy
  let s:lazyFiles=glob(s:toml_dir . 'lazy/*.toml')
  for s:file in split(s:lazyFiles, "\n")
    call dein#load_toml(s:file, { 'lazy': 1 })
  endfor

  call dein#end()
  call dein#save_state()
endif

" install missing plugins
if dein#check_install()
  call dein#install()
endif
