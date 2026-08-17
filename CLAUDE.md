# Project: dotfiles

Personal dotfiles repository managing shell, editor, terminal, and development tool configurations for macOS, Linux, and Windows.

## Structure

```
.
├── zsh/                # Zsh config modules sourced from .zshrc
│   ├── alias.zsh       #   Shell aliases
│   ├── completion.zsh  #   Completion settings
│   ├── directory.zsh   #   Directory navigation options
│   ├── gpg.zsh         #   GPG_TTY export for commit signing
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
│   ├── lint-shell      #   shellcheck + zsh -n over every shell script (same command CI runs)
│   ├── textlint-docs   #   Run textlint/ rules on any repo (symlinked to ~/.local/bin; backs the lint-docs skill)
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
├── textlint/           #   Japanese prose rules for bin/textlint-docs (not a project config)
│   ├── textlintrc.yml  #     Rule set, each relaxation justified inline
│   ├── prh.yml         #     Notation dictionary, split into universal / project-dependent
│   ├── textlintignore  #     Category-level exclusions
│   └── package.json    #     Pinned toolchain (+ package-lock.json)
├── .textlintignore     #   This repo's own exclusions, overriding textlint/textlintignore (not linked to ~/)
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
- **Global agent instructions**: `root/CLAUDE.md` is linked to three destinations, and all three are load-bearing. `~/CLAUDE.md` (Claude Code) and `~/AGENTS.md` (generic `AGENTS.md` readers) are the obvious two. The third, `~/.codex/AGENTS.md`, is required because [Codex reads its global layer only from `$CODEX_HOME`](https://learn.chatgpt.com/docs/agent-configuration/agents-md) — `AGENTS.override.md`, then the first **non-empty** `AGENTS.md` — while its project scope walks from the git root down to cwd and therefore never visits `$HOME`. An empty `~/.codex/AGENTS.md` is skipped, not treated as "no instructions", so the failure is silent: project-level docs keep loading (Codex is pointed at `CLAUDE.md` via `project_doc_fallback_filenames` in the machine-local `~/.codex/config.toml`) and only the global layer goes missing. Verify with `codex debug prompt-input`, which dumps the exact prompt Codex builds — grep it for a phrase unique to `root/CLAUDE.md`. Note the content is Claude-flavoured (tool names like Read/Grep/Edit, `AskUserQuestion`, the subagent guidance); Codex ignores what it cannot map. `~/.codex/config.toml` is deliberately **not** version-controlled — Codex writes per-project `trust_level` and `[notice]` state into it ([upstream issue](https://github.com/openai/codex/issues/14601)).
- **Codex prefix rules**: `root/.codex/rules/default.rules` is linked to `~/.codex/rules` and is the Codex counterpart to `settings.json` permissions. `forbidden` rules carry [`match`/`not_match`](https://learn.chatgpt.com/docs/agent-configuration/rules) example commands that Codex asserts at load time — the only executable tests the rules have. **Run `root/.codex/rules/default.rules.test.sh` after editing.** A violated assertion makes Codex drop the *entire file* silently (exit 0, empty stderr, no TUI warning), so one bad example disables every `forbidden` rule at once — it fails **open**. The test script turns that into a loud failure by asserting known-allowed prefixes are present, and gated ones absent, in `codex debug prompt-input`. Patterns match whole argv **tokens**, never substrings: `--force` does not match `--force-with-lease`, `-fd` does not match `-fdx`, `mkfs` does not match `mkfs.ext4` — each spelling needs its own rule. `env`/`printenv` are `prompt` rather than `forbidden` because a `forbidden` decision cannot be overridden in-session, which would block legitimate shell-environment debugging; note this does not protect file contents, since `cat .env` remains allowed — path-level denial requires a permissions profile (`[permissions.<name>.filesystem]`), not a prefix rule.
- **curl permissions**: `Bash(curl *)` must stay in `permissions.ask` — do **not** replace it with `Bash(curl *<domain>*)` allow rules. Permission patterns match the raw command string with no URL parsing, so `curl *github.com*` also matches `curl https://evil.com/?ref=github.com` ([documented as fragile](https://code.claude.com/docs/en/permissions.md)). Per-domain curl access is instead granted by `root/.claude/hooks/curl-guard.sh`, which parses the argv and checks the real host against the `WebFetch(domain:...)` rules in `settings.json` (one source of truth for both). The hook only ever emits `allow`; anything it cannot verify emits no decision and falls through to that `ask` rule — so removing the `ask` rule silently downgrades every deferral to the auto-mode classifier. Run `root/.claude/hooks/curl-guard.test.sh` after touching it.
- **Destructive filesystem permissions**: `Bash(rm *)` stays in `permissions.ask`; `cp` and `mv` are deliberately not there. An `ask` rule is [evaluated before the auto-mode classifier and can never be auto-approved](https://code.claude.com/docs/en/auto-mode-config#add-a-human-checkpoint), so listing a command there disables the classifier's far better-informed judgement for it — worth it only where a false negative is unrecoverable. That is `rm` (git-untracked files: `.env`, local DBs, `./tmp/` working data), not `cp`/`mv`, whose worst case is a recoverable clobber. The rule is also load-bearing outside auto mode: `default` mode prompts for these anyway, but [`acceptEdits` auto-approves `rm`/`cp`/`mv` inside the working directory with no classifier at all](https://code.claude.com/docs/en/permission-modes#auto-approve-file-edits-with-acceptedits-mode), and `bypassPermissions` skips everything except `ask` rules — so this line is the only gate on `rm` in those modes. Do **not** carve out exceptions with allow globs like `Bash(rm ./tmp/*)`: patterns match the raw string, so that also matches `rm ./tmp/../../important` — the same fragility documented for curl above. Use an argv-parsing hook modelled on `curl-guard.sh` instead.
- **Agent skills**: Skills this repo OWNS live once under `root/.agents/skills/<name>/SKILL.md`. The setup script links each owned skill **individually** into every consumer dir (`~/.agents/skills` cross-tool standard, `~/.claude/skills` Claude Code, `~/.codex/skills` Codex) — never the whole dir as one symlink. This is deliberate: a directory symlink lets tools that auto-install skills (e.g. Cloudflare's installer writing into `~/.agents` or `~/.claude`) create real dirs straight into this repo through the link, polluting it with untracked skills. With per-skill links the consumer dirs stay real directories, so tool-installed skills land beside our symlinks but **outside** the repo (untracked). Trade-off: adding a new owned skill needs a `relink` to appear (`update-all` runs relink, so it self-heals). Add a new owned skill by creating its dir here, then run `relink`. Note: OpenCode reads both `~/.agents/skills` and `~/.claude/skills`, so it may list each skill twice. Skills use Claude frontmatter (`effort`, `allowed-tools`) and `!` command pre-fetch; other tools ignore the extra fields, and `!` lines render as inert text for them. **Ignored means unenforced, which matters for safety:** [Codex reads only `name` and `description`](https://learn.chatgpt.com/docs/build-skills), so a read-only skill's `allowed-tools` fence does not exist there — and `default.rules` pre-approves `git add`/`commit -m`/`push` and `gh pr create`/`edit`, so the very operations such a skill forbids run with no prompt. Any skill whose contract is "read-only" or "never writes/posts" must therefore state that boundary **in the body**, name the concrete commands, and say explicitly that absence of a prompt is not permission. Frontmatter alone is a Claude-only guarantee. This applies to `review-test`, `review-support`, and `check-production-readiness`. `agents/openai.yaml` inside a skill supplies Codex UI metadata and is ignored elsewhere.
- **Japanese prose linting** (`textlint/` + `bin/textlint-docs`, backing the `lint-docs` skill): the rules, the prh dictionary and the exact package versions live in `textlint/` and are the single source of truth. The wrapper **materializes** config *and* `node_modules` into `${XDG_CACHE_HOME:-~/.cache}/textlint-docs` and runs from there. Both halves of that matter. Config and modules must share a directory because textlint resolves rule packages and prh's `rulePaths` relative to the config file, so splitting them breaks resolution from an arbitrary cwd. And that directory must sit **outside** this repo: `bin/` is symlinked into `~/.local/bin` and skill dirs into three agent dirs, so an `npm install` inside the checkout would write thousands of untracked files through those links — the same pollution the per-skill links above avoid. The payoff is that the linted project gets no `.textlintrc`, no devDependency and no `node_modules`, so this runs against repos you do not own or whose toolchain is not JavaScript. Do **not** "simplify" it by depending on a globally installed `textlint`: the global install is per-node-version under volta, so a `volta` node bump silently removes it. `prh.yml` is split into a universal section and a project-dependent one (katakana long-vowel notation, where the `expected` side is just one repo's measured majority) — the skill measures the target repo before applying the latter, and that split is the whole reason the dictionary is portable. Bump versions in `textlint/package.json`, then regenerate the lockfile with `npm install --prefix textlint --package-lock-only`. **The rules do not detect language:** `sentence-length` and `max-comma` fire on English sentences too, so narrowing the target set to Japanese files is the caller's job — the skill does it by counting `。` density (measured here: Japanese files 34–87%, all 28 English files 0%; a hiragana test is not enough, since an English doc's frontmatter triggers can be Japanese). Skipping that step on this repo's own skill docs yields 345 findings of which 332 are noise. **Exclusions are overridable per project:** textlint's own default for `--ignore-path` is `./.textlintignore`, so the wrapper passes the bundled list only when the working directory has no such file (and none was given on the command line). It is a replacement, not a merge. This repo ships its own `/.textlintignore` — **not** linked into `~/` — precisely because the bundled list drops `**/.agents/**` and `**/CLAUDE.md` as vendored agent config, which is true for a repo that consumes skills and false for this one, which authors them; with the bundled list all four Japanese documents here were silently skipped. Findings that come back suspiciously empty are an exclusion problem until proven otherwise — check with `--ignore-path /dev/null`.

## Environment Notes

- **AWS CLI**: Use `/opt/homebrew/bin/aws` to invoke the AWS CLI. The `aws` command is lazy-loaded in zsh, so the bare `aws` may not resolve in non-interactive shells.

## Testing

- **`bin/lint-shell`** static-checks every shell script: `shellcheck -x -P SCRIPTDIR` over the sh/bash ones, `zsh -n` over the zsh ones (shellcheck cannot parse zsh — SC1071). Run it before pushing; `.github/workflows/lint-and-test.yml` runs the same command, so local and CI cannot disagree. Targets are discovered by shebang rather than listed, so a new script is covered automatically. The two exceptions are named in the script: sourced fragments (`bin/init/common.sh`, `links.sh` — no shebang, so they carry a `# shellcheck shell=bash` directive) and the `zsh/` modules.
- GitHub Actions CI runs the platform setup scripts (`.github/workflows/{macos,ubuntu,wsl,windows}-setup.yml`) plus lint and the `curl-guard.sh` hook test (`lint-and-test.yml`).
- **Setup workflows must test the pushed branch.** They `actions/checkout`, symlink the checkout to `~/dotfiles`, and run the bootstrap with `DOTFILES_SKIP_UPDATE=1` so it does not self-update over the branch under test. The earlier form — `curl .../main/bin/init/bootstrap-*.sh | sh`, letting the bootstrap `git clone` the default branch — meant every job validated `main` regardless of the pushed ref, so the checks could not fail on unmerged code. Do not reintroduce a hardcoded `/main/` raw URL or drop the skip flag.
- **`bin/textlint-docs`** is verified by running it, not by a test script: `textlint-docs <some.md>` on a file with known violations. Its failure mode is silent: a misspelled or unknown rule key inside a preset (`sentence-lenght:`, a rule that no longer exists) is **ignored without any error** — verified empirically — so the rule quietly runs with its default settings or not at all, and the only symptom is fewer findings. After editing `textlint/textlintrc.yml`, check the rule IDs in the output rather than the problem count.
- `root/.codex/rules/default.rules.test.sh` is intentionally **not** in CI: it requires the `codex` CLI and exits 0 with "skipping" when absent, which would be a permanently green check proving nothing. Run it locally after editing `default.rules`.
- After changing shell config, verify with a new shell session or `source ~/.zshrc`.
- Zsh startup profiling can be enabled by uncommenting `zprof` lines in `.zshenv` and `.zshrc`.
