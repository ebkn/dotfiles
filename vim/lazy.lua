-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins.instantly" },
    { import = "plugins.lazy" },
  },
  defaults = {
    lazy = false, -- instantly plugins are not lazy by default

    -- Supply-chain hardening: minimum release age.
    -- lazy.nvim has no native "min release age" yet. Track folke/lazy.nvim#2141;
    -- the `commit` hook (PR #2165) is the intended home. Once it merges, uncomment
    -- to skip any commit younger than 7 days on `:Lazy update`, giving the community
    -- time to catch a compromised push before it reaches this machine.
    -- commit = function(target)
    --   local curr = target
    --   while curr and curr:age() < 7 do
    --     curr = curr:parent()
    --   end
    --   return curr
    -- end,
  },
  install = {
    missing = true, -- install missing plugins on startup
  },
  checker = {
    enabled = true, -- automatically check for plugin updates
    notify = false, -- don't show notification on startup
  },
})
