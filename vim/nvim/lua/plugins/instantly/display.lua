return {
  -- color
  {
    "navarasu/onedark.nvim",
    config = function()
      require('onedark').setup({
        toggle_style_key = '<C-e>',
        style = 'warmer'
      })
      require('onedark').load()
    end,
  },

  -- show line that has git diff
  {
    "airblade/vim-gitgutter",
    config = function()
      vim.cmd([[
        let g:gitgutter_async=1
      ]])
    end,
  },

  -- visualize git conflicts
  {
    "akinsho/git-conflict.nvim",
    config = function()
      require('git-conflict').setup()
    end,
  },

  -- visualize colors
  {
    "gorodinskiy/vim-coloresque",
  },

  -- highlight trailing spaces
  {
    "ntpeters/vim-better-whitespace",
  },

  -- indent
  -- {
  --   "shellRaining/hlchunk.nvim",
  --   config = function()
  --     require('hlchunk').setup({})
  --   end,
  -- },

  -- syntax highlight
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = { "go", "typescript", "javascript", "dart", "ruby", "proto", "yaml", "json", "bash", "html", "css", "make", "vim", "lua" },
        sync_install = false,
        highlight = {
          enable = true,
          disable = { "dart" },
        },
      })
    end,
  },

  -- sticky scroll
  {
    "nvim-treesitter/nvim-treesitter-context",
    config = function()
      require('treesitter-context').setup({
        enable = true,
      })
    end,
  },

  -- scroll bar
  {
    "dstein64/nvim-scrollview",
    config = function()
      require('scrollview').setup()
    end,
  },

  -- HlSearch lens
  {
    "kevinhwang91/nvim-hlslens",
    config = function()
      require('hlslens').setup()

      local kopts = {noremap = true, silent = true}

      vim.api.nvim_set_keymap('n', 'n',
          [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]],
          kopts)
      vim.api.nvim_set_keymap('n', 'N',
          [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]],
          kopts)
      vim.api.nvim_set_keymap('n', '*', [[*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', '#', [[#<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'g*', [[g*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'g#', [[g#<Cmd>lua require('hlslens').start()<CR>]], kopts)

      vim.api.nvim_set_keymap('n', '<Leader>l', '<Cmd>noh<CR>', kopts)
    end,
  },
}