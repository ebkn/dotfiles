return {
  -- ansible
  {
    "pearofducks/ansible-vim",
    ft = { "ansible" },
  },

  -- autoclose html(xhtml) tags
  {
    "alvan/vim-closetag",
    ft = { "html", "xhtml", "javascript", "typescript", "javascript.jsx", "typescript.tsx", "javascriptreact", "typescriptreaact" },
    config = function()
      vim.cmd([[
        let g:closetag_filenames='*.html'
        let g:closetag_xhtml_filenames='*.jsx,*.tsx,*.vue'
        let g:closetag_filetypes='html'
        let g:closetag_xhtml_filetypes='jsx,tsx,javascript.jsx,typescript.tsx,vue'
        let g:closetag_emptyTags_caseSensitive=1
        let g:closetag_shortcut='>'
      ]])
    end,
  },

  -- graphql
  {
    "jparise/vim-graphql",
    ft = { "graphql", "javascript", "javascriptreact", "typescript", "typescriptreact" },
  },

  -- toml
  {
    "cespare/vim-toml",
    ft = { "toml" },
  },

  -- css
  {
    "ap/vim-css-color",
  },

  -- c++, proto
  -- run :ClangFormat for format
  {
    "rhysd/vim-clang-format",
    ft = { "cpp", "c" },
    config = function()
      vim.cmd([[
        let g:clang_format#detect_style_file=1
        let g:clang_format#auto_format=1
      ]])
    end,
  },
}