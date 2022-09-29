"--- basic ---
" move line in displayed lines
nnoremap j gj
nnoremap k gk
nnoremap <down> gj
nnoremap <up> gk
" used by copilot
nnoremap <C-j> <nop>

"--- window ---
nnoremap s <Nop>

" move to window
nnoremap sj <C-w>j
nnoremap sk <C-w>k
nnoremap sl <C-w>l
nnoremap sh <C-w>h

" split window
nnoremap ss :<C-u>split<CR>
nnoremap sv :<C-u>vsplit<CR>

" close window
nnoremap sq :<C-u>q<CR>


"--- insert mode ---
" emacs basic keybind
inoremap <C-p> <Up>
inoremap <C-n> <Down>
inoremap <C-b> <Left>
inoremap <C-f> <Right>
inoremap <C-a> <C-o>:call <SID>home()<CR>
function! s:home()
  let start_column=col('.')
  normal! ^
  if col('.')==start_column
  ¦ normal! 0
  endif
  return ''
endfunction
inoremap <C-e> <End>
inoremap <C-d> <Del>
