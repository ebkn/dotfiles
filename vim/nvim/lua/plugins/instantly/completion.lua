return {
  -- completion
  -- install plugins by :CocInstall <plugin>
  -- plugins are saved at ~/.config/coc/extensions
  {
    "neoclide/coc.nvim",
    branch = "release",
    event = "VimEnter",
    config = function()
      -- Set up key mappings after coc is loaded
      vim.api.nvim_create_autocmd("User", {
        pattern = "CocNvimInit",
        callback = function()
          -- Make <CR> to accept selected completion item
          vim.keymap.set("i", "<CR>", function()
            if vim.fn["coc#pum#visible"]() == 1 then
              return vim.fn["coc#pum#confirm"]()
            else
              return vim.api.nvim_replace_termcodes("<C-g>u<CR><C-r>=coc#on_enter()<CR>", true, false, true)
            end
          end, { expr = true, silent = true })
        end,
      })
      vim.cmd([[
        " keymaps
        nmap <silent> gd <Plug>(coc-definition)
        nmap <silent> gy <Plug>(coc-type-definition)
        nmap <silent> gi <Plug>(coc-implementation)
        nmap <silent> gr <Plug>(coc-references)
        nmap <silent> ga <Plug>(coc-codeaction-selected)
        nmap <silent> ca <Plug><coc-codeaction)
        nmap <silent> rn <Plug>(coc-rename)

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
          autocmd FileType go nmap gtj :CocCommand go.tags.add json<cr>
          autocmd BufWritePre *.go :silent call CocAction('runCommand', 'editor.action.organizeImport')
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
