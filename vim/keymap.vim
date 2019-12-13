"--- basic ---
" move line in displayed lines
nnoremap j gj
nnoremap k gk
nnoremap <down> gj
nnoremap <up> gk


"--- window ---
nnoremap s <Nop>

" move to window
nnoremap sj <C-w>j
nnoremap sk <C-w>k
nnoremap sl <C-w>l
nnoremap sh <C-w>h

" split window
nnoremap ss :<C-u>sp<CR>
nnoremap sv :<C-u>vs<CR>

" close window
nnoremap sq :<C-u>q<CR>


"--- insert mode ---
" emacs basic keybind
imap <C-p> <Up>
imap <C-n> <Down>
imap <C-b> <Left>
imap <C-f> <Right>
imap <C-a> <C-o>:call <SID>home()<CR>
function! s:home()
  let start_column = col('.')
  normal! ^
  if col('.') == start_column
  ¦ normal! 0
  endif
  return ''
endfunction
imap <C-e> <End>
imap <C-d> <Del>
