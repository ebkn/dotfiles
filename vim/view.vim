" view
set guifont=SauceCodePro\ Nerd\ Font\ Medium:h14
set ambiwidth=double "show chars like □, ○
set nocursorline     " hide cursor line
set nocursorcolumn   " hide cursor column
set number           " show line number
set signcolumn=yes   " always show signcolumn

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

" show markdown symbols
augroup markdown
  autocmd!
  autocmd FileType markdown set conceallevel=0
augroup END

augroup typescript
  autocmd!
  autocmd BufNewFile,BufRead *.tsx let b:tsx_ext_found=1
  autocmd BufNewFile,BufRead *.tsx set filetype=typescript.tsx
augroup END

set conceallevel=0
