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
        " FZF_DEFAULT_OPTS (.zshenv) sets --delimiter=\t --nth=-1 for
        " tab-delimited shell output (fzf-files --label).
        " fzf.vim commands use different formats, so per-command overrides
        " are needed below (--nth, --accept-nth, --preview, etc.).
        let $FZF_DEFAULT_OPTS = $FZF_DEFAULT_OPTS . ' --accept-nth=1..'
        let g:fzf_layout={ 'window': { 'width': 0.9, 'height': 0.9 } }
        function! s:p(bang, ...)
          let preview_window=get(g:, 'fzf_preview_window', a:bang && &columns>=80 || &columns>=120 ? 'right': '')
          if len(preview_window)
            return call('fzf#vim#with_preview', add(copy(a:000), preview_window))
          endif
          return {}
        endfunction
        command! -bang -nargs=? -complete=dir Files
          \ call fzf#vim#files(<q-args>, {
          \   'options': ['--accept-nth=-1',
          \     '--preview', 'bat --color=always --style=numbers --line-range=:500 {-1}',
          \     '--preview-window', 'right']
          \ }, <bang>0)
        command! -bar -bang -nargs=? -complete=buffer Buffers
          \ call fzf#vim#buffers(<q-args>, s:p(<bang>0, { "placeholder": "{1}" }), <bang>0)
        " rg output is file:line:col:content (colon-delimited).
        " fzf#vim#with_preview sets --delimiter=: which overrides the
        " global tab delimiter, so --nth=-1 from FZF_DEFAULT_OPTS would
        " match only the content field. Override with 1,4.. to search
        " filename (field 1) and content (field 4+), skipping line/col.
        command! -bang -nargs=* Rg
          \ call fzf#vim#grep(
          \   'rg --column --no-heading --color=always --smart-case --hidden -- '.shellescape(<q-args>), 1,
          \   fzf#vim#with_preview({'options': ['--sort', '--nth', '1,4..']}), <bang>0)
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
        nnoremap <C-d> :CocFzfList diagnostics<CR>
        nnoremap <C-e> :CocFzfList outline<CR>
        nnoremap <silent> <space>c :<C-u>CocFzfList commands<CR>
      ]])
    end,
  },
}