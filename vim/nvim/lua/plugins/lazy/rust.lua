return {
  {
    "rust-lang/rust.vim",
    -- Upstream renamed master to main (2026-10). A clone made before that
    -- still has origin/HEAD on master, and lazy.nvim takes the branch from it
    -- when the spec names none -- writing master back into lazy-lock.json,
    -- which bin/lazy-cooldown then holds forever. Named here, it holds on
    -- every machine (bin/lazy-cooldown.md).
    branch = "main",
    ft = { "rust" },
    lazy = true,
    config = function()
      vim.cmd([[
        let g:rustfmt_autosave=1
      ]])
    end,
  },
}
