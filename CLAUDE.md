# Project: dotfiles

Personal dotfiles repository managing shell, editor, terminal, and development tool configurations for macOS and Linux.

## Structure

```
.
├── zsh/                # Zsh config modules sourced from .zshrc
│   ├── alias.zsh       #   Shell aliases
│   ├── completion.zsh  #   Completion settings
│   ├── directory.zsh   #   Directory navigation options
│   ├── history.zsh     #   History settings
│   ├── lang.zsh        #   Language manager lazy-loading
│   ├── path.zsh        #   PATH configuration
│   ├── plugin.zsh      #   Zinit plugin definitions
│   └── .p10k.zsh       #   Powerlevel10k theme config
├── vim/                # Neovim/Vim configuration
│   ├── nvim/lua/plugins/
│   │   ├── instantly/  #   Plugins loaded at startup
│   │   └── lazy/       #   Plugins loaded on demand (filetype, etc.)
│   ├── coc/            #   CoC (Conquer of Completion) extensions config
│   ├── *.vim           #   Vim core config (base, color, keymap, view)
│   └── lazy.lua        #   lazy.nvim bootstrap
├── bin/
│   ├── init/           #   Platform setup scripts (macos.sh, ubuntu.sh)
│   └── install_minimum_vim.sh
├── brewfiles/          #   Homebrew dependency lists by category
│   ├── Brewfile-shell  #     Shell tools (tmux, fzf, ripgrep, etc.)
│   ├── Brewfile-lang   #     Language runtimes and managers
│   ├── Brewfile-cask   #     GUI applications
│   └── Brewfile-mas    #     Mac App Store apps
├── root/               #   Home directory configs (symlinked to ~/)
│   ├── CLAUDE.md       #     Global Claude Code instructions
│   ├── .claude/        #     Claude Code settings and skills
│   └── .codex/         #     Codex rules
├── cursor/             #   Cursor editor settings and keybindings
├── .github/workflows/  #   CI for setup script validation
├── .zshrc              #   Zsh entrypoint (sources zsh/ modules)
├── .zshenv             #   Zsh early env (locale settings)
├── .tmux.conf          #   Tmux configuration
├── .gitconfig          #   Git configuration (includes .gitconfig-ebkn)
├── wezterm.lua         #   WezTerm terminal configuration
├── tmux-restore-tabs   #   Script symlinked to ~/.local/bin/
└── .*                  #   Other dotfiles (.tigrc, .ideavimrc, etc.)
```

`AGENTS.md` is a symlink to this file for Codex compatibility.

## Key Conventions

- **Symlink-based**: Setup scripts in `bin/init/` symlink files from this repo to `~/`. Existing files are backed up to `~/backup/`.
- **Modular zsh**: Shell config is split by concern in `zsh/` and sourced from `.zshrc`. Environment variables that must be set early go in `.zshenv`.
- **Tmux auto-start**: `.zshrc` starts tmux automatically and exits the shell when tmux closes.
- **Lazy loading**: Language managers and CLI tools (nvm, pyenv, rbenv, swiftenv, gcloud, kubectl, npm, aws) are lazy-loaded via function-wrapping in `zsh/lang.zsh` for fast shell startup.
- **Plugin managers**: Neovim uses lazy.nvim; Zsh uses Zinit.

## Editing Guidelines

- **Zsh config**: Identify the correct module in `zsh/` rather than editing `.zshrc` directly. The `.zshrc` itself should only contain top-level shell options and source lines.
- **Neovim plugins**: Plugin config lives in `vim/nvim/lua/plugins/`, split into `instantly/` (always loaded) and `lazy/` (on-demand by filetype). Core Vim settings are in `vim/*.vim`.
- **Brewfiles**: Changes should go in the appropriate category file under `brewfiles/` (shell, lang, cask, mas).
- **New dotfiles**: When adding a new dotfile, add the corresponding `ln -sf` line in `bin/init/macos.sh` (and `ubuntu.sh` if cross-platform).
- **Home directory agent config**: Global Claude Code/Codex settings live in `root/` and are symlinked to `~/` by the setup script.

## Testing

- GitHub Actions CI runs `bin/init/macos.sh` (`.github/workflows/macos-setup.yml`) and `bin/init/ubuntu.sh` (`.github/workflows/ubuntu-setup.yml`) to verify setup scripts.
- After changing shell config, verify with a new shell session or `source ~/.zshrc`.
- Zsh startup profiling can be enabled by uncommenting `zprof` lines in `.zshenv` and `.zshrc`.
