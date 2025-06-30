return {
  {
    "ruanyl/vim-gh-line",
    config = function()
      vim.cmd([[
        let g:gh_line_map_default=0
        let g:gh_line_blame_map_default=1
        let g:gh_line_map='<leader>gh'
      ]])
    end,
  },
}