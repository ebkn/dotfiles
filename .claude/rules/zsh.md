---
paths:
  - "zsh/**"
  - ".zshrc"
  - ".zshenv"
---

# zsh config

Read [zsh/README.md](../../zsh/README.md) first; per-module notes are in [ssh.md](../../zsh/ssh.md), [git.md](../../zsh/git.md), [alias.md](../../zsh/alias.md).

- **Edit the module in `zsh/` that owns the concern, not `.zshrc`.** Module order is not free and the constraint is invisible: `alias.zsh` must precede `git.zsh`.
- **`.zshrc` finds `zsh/` via `${(%):-%N}`, never `$0`**, so any checkout loads its own modules. Pinned by `zsh/zshrc-resolve.test.zsh`.
- **Never `stat` a path under `/home` on macOS** — autofs makes it ~16 ms per stat, on every shell start. Guard on `$OSTYPE`.
- Startup is kept fast: `nvm`, `gcloud` and `kubectl` are lazy-loaded in `zsh/lang.zsh`; don't initialise them eagerly elsewhere.
- `.zshrc` starts tmux and exits the shell when tmux closes.
- Check changes with `/bin/zsh -n` as well as Homebrew's zsh: CI's older zsh is stricter.
