return {
  -- language packs
  {
    "sheerun/vim-polyglot",
    init = function()
      vim.cmd([[
        let g:polyglot_disabled=['elm']
      ]])
    end,
  },

  -- toggle comments
  { "numToStr/Comment.nvim", opts = {} },

  -- change operator by s+a/d/r
  { "kana/vim-operator-user" },

  {
    "rhysd/vim-operator-surround",
    dependencies = { "kana/vim-operator-user" },
    config = function()
      vim.cmd([[
        nnoremap <silent>sa <Plug>(operator-surround-append)
        nnoremap <silent>sd <Plug>(operator-surround-delete)
        nnoremap <silent>sr <Plug>(operator-surround-replace)
      ]])
    end,
  },

  -- for vim-delve
  { "benmills/vimux" },

  -- autoclose parenthesis
  { "windwp/nvim-autopairs", opts = {} },

  -- wrap/unwrap arguments,lists,dict
  {
    "FooSoft/vim-argwrap",
    config = function()
      vim.cmd([[
        nnoremap <C-a> :ArgWrap<CR>
        let g:argwrap_tail_comma=1
      ]])
    end,
  },
}
