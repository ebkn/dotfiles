# Project: dotfiles

Personal dotfiles repository managing shell, editor, terminal, and development tool configurations for macOS, Linux, and Windows.

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
├── autohotkey/         # AutoHotkey v2 scripts for Windows
│   └── keyremap.ahk   #   Key remapping (CapsLock→Ctrl, Alt→IME switch)
├── bin/
│   ├── init/           #   Platform setup scripts (macos.sh, ubuntu.sh, wsl.sh, windows.ps1)
│   │   ├── common.sh   #     Shared setup helpers (link_with_backup, etc.)
│   │   └── links.sh    #     link_dotfiles(): re-syncable $HOME symlinks (shared by macos.sh + relink)
│   ├── wsl/            #   WSL-only helper scripts (e.g. notify-send OSC 9 shim)
│   ├── relink          #   Re-sync symlinks from link_dotfiles() (drift check + prompt; called by update-all)
│   ├── fzf-files       #   List git-changed files first for fzf (symlinked to ~/.local/bin)
│   ├── git-generated   #   Locally hide linguist-generated files from diffs via .git/info/attributes
│   └── install_minimum_vim.sh
├── brewfiles/          #   Homebrew dependency lists by category
│   ├── Brewfile-shell  #     Shell tools (tmux, fzf, ripgrep, etc.)
│   ├── Brewfile-lang   #     Language runtimes and managers
│   ├── Brewfile-xcode  #     Swift tools requiring Xcode.app
│   ├── Brewfile-cask   #     GUI applications
│   └── Brewfile-mas    #     Mac App Store apps
├── root/               #   Home directory configs (symlinked to ~/)
│   ├── CLAUDE.md       #     Global Claude Code instructions
│   ├── .agents/skills/ #     Cross-tool agent skills (single source of truth)
│   ├── .claude/        #     Claude Code settings and hooks
│   ├── .codex/         #     Codex prefix rules
│   └── opencode/       #     OpenCode config → ~/.config/opencode
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
- **New dotfiles**: For a plain, order-independent `$HOME` symlink, add a `link_with_backup` line to `link_dotfiles()` in `bin/init/links.sh` — that is the single source of truth shared by `bin/init/macos.sh` and `bin/relink`, so `update-all` picks it up on already-provisioned machines (no init re-run needed). For `ubuntu.sh`/`wsl.sh` add the line inline (they are not yet migrated to `link_dotfiles`). Keep order-sensitive links (`.zshrc`/`.zshenv`, `.npmrc`) or links wrapped in special logic inline in the platform init script.
- **Re-syncing symlinks**: `update-all` runs `relink` at the end; it reports drift and asks before creating/fixing links. Run `relink` directly anytime to sync.
- **Platform-specific binaries**: Helper scripts that only make sense on one OS go under `bin/<platform>/` (e.g. `bin/wsl/`). Cross-platform helpers stay at `bin/` root. Symlink them from the matching `bin/init/<platform>.{sh,ps1}`.
- **Home directory agent config**: Global Claude Code/Codex settings live in `root/` and are symlinked to `~/` by the setup script.
- **curl permissions**: `Bash(curl *)` must stay in `permissions.ask` — do **not** replace it with `Bash(curl *<domain>*)` allow rules. Permission patterns match the raw command string with no URL parsing, so `curl *github.com*` also matches `curl https://evil.com/?ref=github.com` ([documented as fragile](https://code.claude.com/docs/en/permissions.md)). Per-domain curl access is instead granted by `root/.claude/hooks/curl-guard.sh`, which parses the argv and checks the real host against the `WebFetch(domain:...)` rules in `settings.json` (one source of truth for both). The hook only ever emits `allow`; anything it cannot verify emits no decision and falls through to that `ask` rule — so removing the `ask` rule silently downgrades every deferral to the auto-mode classifier. Run `root/.claude/hooks/curl-guard.test.sh` after touching it.
- **Agent skills**: Skills this repo OWNS live once under `root/.agents/skills/<name>/SKILL.md`. The setup script links each owned skill **individually** into every consumer dir (`~/.agents/skills` cross-tool standard, `~/.claude/skills` Claude Code, `~/.codex/skills` Codex) — never the whole dir as one symlink. This is deliberate: a directory symlink lets tools that auto-install skills (e.g. Cloudflare's installer writing into `~/.agents` or `~/.claude`) create real dirs straight into this repo through the link, polluting it with untracked skills. With per-skill links the consumer dirs stay real directories, so tool-installed skills land beside our symlinks but **outside** the repo (untracked). Trade-off: adding a new owned skill needs a `relink` to appear (`update-all` runs relink, so it self-heals). Add a new owned skill by creating its dir here, then run `relink`. Note: OpenCode reads both `~/.agents/skills` and `~/.claude/skills`, so it may list each skill twice. Skills use Claude frontmatter (`effort`, `allowed-tools`) and `!` command pre-fetch; other tools ignore the extra fields, and `!` lines render as inert text for them. `agents/openai.yaml` inside a skill supplies Codex UI metadata and is ignored elsewhere.

## Environment Notes

- **AWS CLI**: Use `/opt/homebrew/bin/aws` to invoke the AWS CLI. The `aws` command is lazy-loaded in zsh, so the bare `aws` may not resolve in non-interactive shells.

## Testing

- GitHub Actions CI runs `bin/init/macos.sh` (`.github/workflows/macos-setup.yml`) and `bin/init/ubuntu.sh` (`.github/workflows/ubuntu-setup.yml`) to verify setup scripts.
- After changing shell config, verify with a new shell session or `source ~/.zshrc`.
- Zsh startup profiling can be enabled by uncommenting `zprof` lines in `.zshenv` and `.zshrc`.
