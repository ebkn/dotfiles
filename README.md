# ebkn's dotfiles

Personal dotfiles for macOS and Linux.

## Install

```sh
# macOS
xcode-select --install
curl -s https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/macos.sh | zsh
```

```sh
# Ubuntu
curl -s https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/ubuntu.sh | bash
```

## What's included

- **Zsh** — modular config in `zsh/`, plugins via [Zinit](https://github.com/zdharma-continuum/zinit)
- **Neovim** — plugins via [lazy.nvim](https://github.com/folke/lazy.nvim), config in `vim/`
- **Tmux / WezTerm** — terminal multiplexer and emulator configs
- **Homebrew** — dependency lists split by category in `brewfiles/`
- **Git / Cursor / Claude Code** — editor and tool settings
