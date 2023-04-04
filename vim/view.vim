" view

set ambiwidth=double  " show chars like □, ○
set cursorline        " show cursor line
set nocursorcolumn    " hide cursor column
set noshowcmd         " hide cmd
set noshowmode        " hide mode
set number            " show line number
set signcolumn=yes    " always show signcolumn
set showmatch         " show matched braces
set matchtime=1       " show matched braces instantly
set laststatus=2      " always show statusline
set display+=lastline " display long line

" show zenkaku space
function! ZenkakuSpace()
  highlight ZenkakuSpace cterm=reverse ctermfg=red guibg=black
endfunction
if has('syntax')
  augroup zenkaku-space
    autocmd!
    autocmd ColorScheme * call ZenkakuSpace()
    autocmd VimEnter,WinEnter,BufRead * match ZenkakuSpace /　/
  augroup END
  call ZenkakuSpace()
endif

augroup typescript
  autocmd!
  autocmd BufNewFile,BufRead *.tsx let b:tsx_ext_found=1
  autocmd BufNewFile,BufRead *.tsx set filetype=typescript.tsx
augroup END
