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

## Tmux Keybindings

Prefix: `C-q`

### Session

| Key | Action |
|-----|--------|
| `C-q N` | Create new session |

### Window

| Key | Action |
|-----|--------|
| `F12` | Kill current window (no prefix) |
| `C-q v` | Split vertically (side by side) |
| `C-q s` | Split horizontally (top/bottom) |

### Pane

| Key | Action |
|-----|--------|
| `C-q h/j/k/l` | Select pane (left/down/up/right) |
| `C-q H/J/K/L` | Resize pane (repeatable) |
| `C-q q` | Kill pane (with confirmation) |
| `C-q p` | Popup terminal (80%x80%) |
| `C-q t` | Popup tig (80%x80%) |
| `C-q g` | Open GitHub PR/repo in browser |

### Copy Mode

| Key | Action |
|-----|--------|
| `C-q u` | Enter copy mode |
| `v` | Begin selection |
| `y` / `M-c` | Copy to clipboard (pbcopy) |
| `Escape` / `C-c` | Exit copy mode |

### Nested Tmux (SSH)

| Key | Action |
|-----|--------|
| `C-q C-q` | Send prefix to inner tmux |
