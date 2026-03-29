return {
  -- Colorscheme plugin. Provides the highlight definitions loaded by
  -- `colorscheme everforest` in vim/color.vim.
  { "sainnhe/everforest" },

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
  { "akinsho/git-conflict.nvim", opts = {} },

  -- visualize colors
  { "gorodinskiy/vim-coloresque" },

  -- highlight trailing spaces
  { "ntpeters/vim-better-whitespace" },

  -- indent
  -- {
  --   "shellRaining/hlchunk.nvim",
  --   config = function()
  --     require('hlchunk').setup({})
  --   end,
  -- },

  -- syntax highlight (parsers installed manually via :TSInstall)
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      -- Neovim 0.10+ enables treesitter highlight automatically; disable for dart
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "dart",
        callback = function(args)
          vim.treesitter.stop(args.buf)
        end,
      })
    end,
  },

  -- markdown viewer
  {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.nvim' },            -- if you use the mini.nvim suite
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.icons' },        -- if you use standalone mini plugins
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      heading = {
        icons = { '# ', '## ', '### ', '#### ', '##### ', '###### ' },
      },
      code = {
        border = 'thin',
      },
      html = {
        comment = { conceal = false },
      },
      -- sign_text with 3-cell nerd font icons causes nvim_buf_set_extmark errors on nvim 0.11.x
      sign = { enabled = false },
    },
  },

  -- sticky scroll
  {
    "nvim-treesitter/nvim-treesitter-context",
    opts = { enable = true },
  },

  -- scroll bar
  { "dstein64/nvim-scrollview", opts = {} },

  -- HlSearch lens
  {
    "kevinhwang91/nvim-hlslens",
    config = function()
      require('hlslens').setup()

      local kopts = {noremap = true, silent = true}

      vim.api.nvim_set_keymap('n', 'n',
          [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
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
