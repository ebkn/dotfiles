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

### Session Persistence (resurrect + continuum)

Sessions are auto-saved every 3 minutes and auto-restored on tmux server start.
Saves include session/window/pane layout, working directories, and running commands.
Files are stored in `~/.local/share/tmux/resurrect/`.

| Key | Action |
|-----|--------|
| `C-q C-s` | Manual save |
| `C-q C-r` | Manual restore |

### Nested Tmux (SSH)

| Key | Action |
|-----|--------|
| `C-q C-q` | Send prefix to inner tmux |

## WezTerm Keybindings

| Key | Action |
|-----|--------|
| `C-t` | New tab (inherits current directory) |
| `Cmd-w` | Close tmux window (with confirmation) |
| `Cmd-Click` | Open link under cursor |
| `Right-Click` | Paste from clipboard |

## Neovim Keybindings

### Movement

| Key | Action |
|-----|--------|
| `j` / `k` | Move by display lines (not physical lines) |

### Window

| Key | Action |
|-----|--------|
| `sh/sj/sk/sl` | Select window (left/down/up/right) |
| `ss` | Split horizontally |
| `sv` | Split vertically |
| `sq` | Close window |
| `s+` / `s-` | Resize height (±10) |
| `s>` / `s<` | Resize width (±10) |
| `s=` | Equalize window sizes |

### Insert Mode (Emacs-style)

| Key | Action |
|-----|--------|
| `C-p` / `C-n` | Up / Down |
| `C-b` / `C-f` | Left / Right |
| `C-a` / `C-e` | Home / End |
| `C-d` | Delete |

### File Navigation (fzf)

| Key | Action |
|-----|--------|
| `C-f` | Find files |
| `C-g` | Ripgrep search |
| `C-b` | Open buffers |
| `C-d` | Diagnostics list |
| `C-e` | Outline (symbols) |
| `<space>c` | CoC commands |

### File Explorer (fern)

| Key | Action |
|-----|--------|
| `C-s` | Toggle sidebar |
| `l` / `h` | Expand / Collapse |
| `N` | New file |
| `D` | Delete |
| `c` / `m` | Copy / Move |
| `R` | Reload |

### LSP (coc.nvim)

| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gy` | Go to type definition |
| `gi` | Go to implementation |
| `gr` | Show references |
| `ca` | Code action |
| `ga` (visual) | Code action (selection) |
| `rn` | Rename symbol |

### Completion

| Key | Action |
|-----|--------|
| `CR` | Accept completion |
| `C-k` | Trigger Copilot suggestion |
| `C-x` | Next Copilot suggestion |

### Search (hlslens)

| Key | Action |
|-----|--------|
| `n` / `N` | Next / Previous result (with lens) |
| `*` / `#` | Search word forward / backward |
| `<leader>l` | Clear search highlight |

### Text Editing

| Key | Action |
|-----|--------|
| `sa` / `sd` / `sr` | Add / Delete / Replace surrounding |
| `C-a` | Wrap/unwrap arguments |
| `<leader>gh` | Open current line in GitHub |
