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

  -- syntax highlight (main branch required for Neovim 0.12+)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
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
        -- code.style defaults to 'full' which enables language-based syntax
        -- highlighting via treesitter. Embedded languages require their
        -- parser to be installed (`:TSInstall <lang>`).
      },
      -- Keep raw "-" / "*" / "+" markers instead of bullet icons.
      bullet = { enabled = false },
      html = {
        comment = { conceal = false },
      },
      -- sign_text with 3-cell nerd font icons causes nvim_buf_set_extmark errors on nvim 0.11.x
      sign = { enabled = false },
    },
    config = function(_, opts)
      require('render-markdown').setup(opts)
      -- Dim HTML comments (<!-- ... -->) in markdown. The html treesitter
      -- parser is not bundled with nvim 0.12 and nvim-treesitter main
      -- branch does not auto-install it, so <!-- --> text renders as plain
      -- Normal. A vim syntax region gives us a reliable, parser-free hook.
      local function set_hl()
        vim.api.nvim_set_hl(0, 'MarkdownHtmlComment', { fg = '#555f65', italic = true })
      end
      set_hl()
      vim.api.nvim_create_autocmd('ColorScheme', { pattern = '*', callback = set_hl })
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'markdown',
        callback = function()
          vim.cmd([[syntax region MarkdownHtmlComment start=/<!--/ end=/-->/ containedin=ALL keepend]])
        end,
      })
    end,
  },

  -- sticky scroll
  {
    "nvim-treesitter/nvim-treesitter-context",
    opts = {
      enable = true,
      on_attach = function(buf)
        return vim.bo[buf].filetype ~= "markdown"
      end,
    },
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
