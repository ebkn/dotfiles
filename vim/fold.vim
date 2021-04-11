" fold
" zc : close all folds under the cursor
" zO : open all folds under the cursor
" zM : close all folds in file
" zR : open all folds in file
set foldmethod=syntax
set foldlevelstart=0
set foldnestmax=2
function! CustomFoldText()
  let length=v:foldend - v:foldstart + 1
  let firstLine=getline(v:foldstart)
  let txt='+ ' . firstLine . ' -- ' . length . ' lines'
  return txt
endfunction
set foldtext=CustomFoldText() " set custom fold text

" save fold state
augroup fold
  autocmd!
  autocmd BufWinLeave * silent! mkview
  autocmd BufWinEnter * silent! loadview
  autocmd BufWritePost * normal! zv
augroup END
