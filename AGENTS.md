# Project: dotfiles

Personal dotfiles repository managing shell, editor, terminal, and development tool configurations for macOS and Linux.

## Structure

```
.
├── zsh/              # Zsh config modules (.zshrc, aliases, path, plugins, etc.)
├── vim/              # Neovim/Vim config (lazy.nvim plugins, keymaps, CoC)
├── bin/init/         # Platform-specific setup scripts (macos.sh, ubuntu.sh)
├── brewfiles/        # Homebrew dependency lists by category
├── cursor/           # Cursor editor settings
├── .claude/          # Claude Code settings
├── root/             # Home directory CLAUDE.md (symlinked to ~/)
├── .tmux.conf        # Tmux configuration
├── .gitconfig        # Git configuration
├── wezterm.lua       # Wezterm terminal configuration
└── .*                # Other dotfiles (.tigrc, .ideavimrc, etc.)
```

## Key Conventions

- **Symlink-based**: Setup scripts symlink files from this repo to `~/`. Existing files are backed up to `~/backup/`.
- **Modular zsh**: Shell config is split by concern (`alias.zsh`, `path.zsh`, `lang.zsh`, etc.) and sourced from `.zshrc`.
- **Lazy loading**: Heavy language managers (nvm, pyenv, rbenv) are lazy-loaded in `zsh/lang.zsh` for fast shell startup.
- **Plugin manager**: Neovim uses lazy.nvim; Zsh uses Zinit.

## Editing Guidelines

- When modifying shell config, identify the correct module in `zsh/` rather than editing `.zshrc` directly.
- Neovim plugin config lives in `vim/nvim/lua/plugins/` split into `instantly/` (always loaded) and `lazy/` (on-demand).
- Brewfile changes should go in the appropriate category file under `brewfiles/`.
- Setup scripts in `bin/init/` create symlinks. When adding a new dotfile, add the corresponding `ln -sf` line there.

## Testing

- GitHub Actions CI runs `bin/init/macos.sh` and `bin/init/ubuntu.sh` to verify setup scripts work.
- After changing shell config, verify with a new shell session or `source ~/.zshrc`.
