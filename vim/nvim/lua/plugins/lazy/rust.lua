return {
  {
    "rust-lang/rust.vim",
    ft = { "rust" },
    lazy = true,
    config = function()
      vim.cmd([[
        let g:rustfmt_autosave=1
      ]])
    end,
  },
}
