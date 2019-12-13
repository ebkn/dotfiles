" enable syntax
syntax on

" enable 256 colors
set t_Co=256

" tmux
if (empty($TMUX))
  if (has("nvim"))
    let $NVIM_TUI_ENABLE_TRUE_COLOR=1
  endif
  if (has("termguicolors"))
    set termguicolors
  endif
endif

" set color scheme
colorscheme onedark
