---
paths:
  - "vim/**"
---

# Neovim config

- Plugins (lazy.nvim) live in `vim/nvim/lua/plugins/`: `instantly/` is always loaded, `lazy/` loads on demand by filetype. Core settings are in `vim/*.vim`.
- **coc.nvim has no trust model**: a cloned repo's `.vim/coc-settings.json` can spawn an arbitrary executable just by opening a file in it. The only gate is not starting coc. Four things silently break it — read [vim/coc-trust.md](../../vim/coc-trust.md) before touching `vim/nvim/lua/coc_trust.lua`.
