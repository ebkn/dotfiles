" Use 24-bit RGB color in the terminal.
" This works because tmux's terminal-overrides declare RGB capability
" for the outer terminal (WezTerm), and default-terminal is tmux-256color
" which Neovim recognizes as true-color capable.
set termguicolors

" Colorscheme applied to the editor UI and syntax highlighting.
" The plugin is loaded by vim/nvim/lua/plugins/instantly/display.lua.
" Keep in sync with WezTerm's color_scheme (wezterm.lua) for visual consistency.
" 'hard' background gives a darker base than WezTerm's default palette,
" creating subtle contrast between the editor and terminal chrome.
let g:everforest_background = 'hard'
colorscheme everforest
