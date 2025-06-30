return {
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      require('lualine').setup({
        options = {
          theme = 'onedark',
          colored = true,
          path = 1,
        },
        sections = {
          lualine_b = {'diff', 'diagnostics'},
          lualine_x = {'filetype'},
          lualine_y = {},
        },
      })
    end,
  },
}