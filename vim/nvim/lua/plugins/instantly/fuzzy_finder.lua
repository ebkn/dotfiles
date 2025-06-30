return {
  -- fuzzy finder
  -- requires `$ brew install fzf`
  {
    "junegunn/fzf",
    build = function()
      vim.fn["fzf#install"]()
    end,
    config = function()
      vim.cmd([[
        set rtp+=/usr/local/opt/fzf
        set rtp+=/opt/homebrew/opt/fzf
      ]])
    end,
  },

  -- use bat for syntax highlight preview window
  {
    "junegunn/fzf.vim",
    dependencies = { "junegunn/fzf" },
    config = function()
      vim.cmd([[
        set rtp+=/usr/local/opt/fzf
        set rtp+=/opt/homebrew/opt/fzf
        let g:fzf_layout={ 'window': { 'width': 0.9, 'height': 0.9 } }
        function! s:p(bang, ...)
          let preview_window=get(g:, 'fzf_preview_window', a:bang && &columns>=80 || &columns>=120 ? 'right': '')
          if len(preview_window)
            return call('fzf#vim#with_preview', add(copy(a:000), preview_window))
          endif
          return {}
        endfunction
        command! -bang -nargs=? -complete=dir Files
          \ call fzf#vim#files(<q-args>, s:p(<bang>0), <bang>0)
        command! -bar -bang -nargs=? -complete=buffer Buffers
          \ call fzf#vim#buffers(<q-args>, s:p(<bang>0, { "placeholder": "{1}" }), <bang>0)
        command! -bang -nargs=* Rg
          \ call fzf#vim#grep(
          \   'rg --column --no-heading --color=always --smart-case --hidden -- '.shellescape(<q-args>), 1,
          \   fzf#vim#with_preview(), <bang>0)
        nnoremap <C-f> :Files<CR>
        nnoremap <C-g> :Rg<Space>
        nnoremap <C-b> :Buffers<CR>
      ]])
    end,
  },

  {
    "antoinemadec/coc-fzf",
    dependencies = { "junegunn/fzf.vim", "neoclide/coc.nvim" },
    config = function()
      vim.cmd([[
        nnoremap <C-d> :CocFzfList dianostics<CR>
        nnoremap <C-e> :CocFzfList outline<CR>
        nnoremap <silent> <space>c :<C-u>CocFzfList commands<CR>
      ]])
    end,
  },
}