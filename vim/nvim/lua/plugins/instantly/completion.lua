return {
  -- completion
  -- install plugins by :CocInstall <plugin>
  -- plugins are saved at ~/.config/coc/extensions
  {
    "neoclide/coc.nvim",
    branch = "release",
    config = function()
      vim.cmd([[
        " tab for trigger completion
        " inoremap <silent><expr> <TAB>
        "         \ coc#pum#visible() ? coc#pum#next(1) :
        "         \ CheckBackspace() ? "\<Tab>" :
        "         \ coc#refresh()
        " function! CheckBackspace() abort
        "   let col=col('.') - 1
        "   return !col || getline('.')[col - 1] =~# '\s'
        " endfunction
        " inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

        " make <CR> to accept selected completion item
        inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm() : "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

        " keymaps
        nmap <silent> gd <Plug>(coc-definition)
        nmap <silent> gy <Plug>(coc-type-definition)
        nmap <silent> gi <Plug>(coc-implementation)
        nmap <silent> gr <Plug>(coc-references)
        nmap <silent> ga <Plug>(coc-codeaction-selected)
        nmap <silent> ca <Plug><coc-codeaction)
        nmap <silent> rn <Plug>(coc-rename)

        " Prettier command
        command! -nargs=0  Prettier :CocCommand prettier.forceFormatDocument

        " filetype
        let g:coc_filetype_map={
          \ 'typescript.jsx': 'typescriptreact',
          \ 'javascript.jsx': 'javascriptreact',
          \ }

        augroup coc
          autocmd!

          " show signature help
          autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')

          " highlight symbols
          autocmd CursorHold * silent call CocActionAsync('highlight')

          " Go
          " add tags
          autocmd FileType go nmap gtj :CocCommand go.tags.add json<cr>
          " add missing imports
          autocmd BufWritePre *.go :silent call CocAction('runCommand', 'editor.action.organizeImport')
          " go tests
          command! -nargs=0 GoTests :CocCommand go.test.generate.function
        augroup END
      ]])
    end,
  },

  -- proto
  {
    "dense-analysis/ale",
    config = function()
      vim.cmd([[
        let g:ale_linters={
          \ 'proto': ['buf-lint'],
        \}
        let g:ale_fixers={
        \   'proto': ['buf-format'],
        \}
        let g:ale_fix_on_save=1
      ]])
    end,
  },

  -- Copilot
  {
    "github/copilot.vim",
    config = function()
      vim.cmd([[
        " accept suggestion by C-j
        imap <silent> <C-k> <Plug>(copilot-suggest)
        imap <silent> <C-x> <Plug>(copilot-next)
        let b:copilot_enabled=v:true

        " bind accept action to <C-n>
        " imap <silent><script><expr> <C-n> copilot#Accept("\<CR>")
        " let g:copilot_no_tab_map=v:true
      ]])
    end,
  },
}
