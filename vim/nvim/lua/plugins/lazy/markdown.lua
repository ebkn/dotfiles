return {
  -- :PrevimOpen
  {
    "previm/previm",
    ft = { "markdown" },
    config = function()
      vim.cmd([[
        let g:previm_open_cmd='open'
        let g:vim_markdown_conceal=0
      ]])
    end,
  },
}